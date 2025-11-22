// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Memory Access Controller
// キャッシュとメモリの間に存在し、
// メモリアクセス要求の形式を変換する。
// ICacheとDCacheからのアクセスの調停も行う。
//

`include "BasicMacros.sv"

import BasicTypes::*;
import CacheSystemTypes::*;
import MemoryTypes::*;
import MemoryMapTypes::*;

module MemoryAccessController (
    CacheSystemIF.MemoryAccessController port,
    input
        MemAccessSerial     nextMemReadSerial,   // 次の読み出し要求シリアル(id)
        MemWriteSerial      nextMemWriteSerial,  // 次の書き込み要求シリアル(id)
        MemoryEntryDataPath memReadData,
        logic               memReadDataReady,
        MemAccessSerial     memReadSerial,       // メモリ読出しデータのシリアル
        ThreadID            memReadTid,          // メモリ読出しデータに対応するスレッドID
        MemAccessResponse   memAccessResponse,   // メモリ書き込み完了通知
        logic               memAccessReadBusy,
        logic               memAccessWriteBusy,
    output
        PhyAddrPath         memAccessAddr,
        MemoryEntryDataPath memAccessWriteData,
        logic               memAccessRE,
        logic               memAccessWE,
        ThreadID            memAccessTid        // NEW: メモリアクセスに付随するTID
);

    // ICache/DCacheからの要求を受理するか否か
    logic icAck;
    logic dcAck;

    // NOTE:
    // nextMemReadSerial / nextMemWriteSerial のインクリメントは Memory 側で行う。
    // ここでは「どの要求を受け付けたか」だけを決める。

    // メモリへのアクセス要求
    always_comb begin
        // デフォルト
        icAck = FALSE;
        dcAck = FALSE;

        // Read busy / write busy に応じて arbitrating
        if (!memAccessReadBusy && port.icMemAccessReq.valid) begin
            // I-Cache の読み出し要求を受理
            icAck = TRUE;
        end
        else if (!memAccessReadBusy &&
                 port.dcMemAccessReq.valid &&
                 (port.dcMemAccessReq.we == FALSE)) begin
            // D-Cache の読み出し要求を受理
            dcAck = TRUE;
        end
        else if (!memAccessWriteBusy &&
                 port.dcMemAccessReq.valid &&
                 (port.dcMemAccessReq.we == TRUE)) begin
            // D-Cache の書き込み要求を受理
            dcAck = TRUE;
        end

        // 実際のメモリアクセス信号生成
        if (icAck) begin
            memAccessAddr       = port.icMemAccessReq.addr;
            memAccessWriteData  = '0;
            memAccessRE         = TRUE;
            memAccessWE         = FALSE;
            memAccessTid        = port.icMemAccessReq.tid;   // NEW: I-Cache からの TID を付与
        end
        else if (dcAck) begin
            memAccessAddr       = port.dcMemAccessReq.addr;
            memAccessWriteData  = port.dcMemAccessReq.data;
            memAccessRE         = (port.dcMemAccessReq.we ? FALSE : TRUE);
            memAccessWE         = (port.dcMemAccessReq.we ? TRUE  : FALSE);
            memAccessTid        = port.dcMemAccessReq.tid;   // NEW: D-Cache からの TID を付与
        end
        else begin
            memAccessAddr       = '0;
            memAccessWriteData  = '0;
            memAccessRE         = FALSE;
            memAccessWE         = FALSE;
            memAccessTid        = '0; // don't care
        end

        // Ack for Request
        port.icMemAccessReqAck.ack    = icAck;
        port.icMemAccessReqAck.serial = nextMemReadSerial; // I-Cache は読み出しのみ

        port.dcMemAccessReqAck.ack    = dcAck;
        // D-Cache の要求は書き込みと読み出しの2種類あり，
        // 読み出し側シリアルと書き込み側シリアルを個別に管理
        port.dcMemAccessReqAck.serial  = nextMemReadSerial;
        port.dcMemAccessReqAck.wserial = nextMemWriteSerial;
    end

    // メモリの読出し結果
    always_comb begin
        // I-Cache 用の読み出し結果
        port.icMemAccessResult.valid  = memReadDataReady;
        port.icMemAccessResult.serial = memReadSerial;
        port.icMemAccessResult.data   = memReadData;
        port.icMemAccessResult.tid    = memReadTid;   // NEW: Memory から返却された TID を透過

        // D-Cache 用の読み出し結果
        port.dcMemAccessResult.valid  = memReadDataReady;
        port.dcMemAccessResult.serial = memReadSerial;
        port.dcMemAccessResult.data   = memReadData;
        port.dcMemAccessResult.tid    = memReadTid;   // 同じく透過

        // 書き込み完了通知
        port.dcMemAccessResponse      = memAccessResponse;
    end

    // 現在の実装では、キャッシュラインのデータ幅とメモリの入出力データ幅は
    // 同じである必要がある。
    `RSD_STATIC_ASSERT(
        $bits(ICacheLinePath) == $bits(MemoryEntryDataPath),
        ("The data width of a cache line(%x) and a memory entry(%x) are not matched.",
         $bits(ICacheLinePath), $bits(MemoryEntryDataPath))
    );
    `RSD_STATIC_ASSERT(
        $bits(DCacheLinePath) == $bits(MemoryEntryDataPath),
        ("The data width of a cache line(%x) and a memory entry(%x) are not matched.",
         $bits(DCacheLinePath), $bits(MemoryEntryDataPath))
    );

endmodule

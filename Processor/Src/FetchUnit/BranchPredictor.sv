// Copyright 2019- RSD contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.


//
// Branch predictor
//
// SMT Update: This wrapper passes the thread-aware interfaces (port, next, ctrl)
// down to the specific predictor implementation.
//

import BasicTypes::*;
import FetchUnitTypes::*;

`define USE_GSHARE

module BranchPredictor(
    NextPCStageIF.BranchPredictor port,
    FetchStageIF.BranchPredictor next,
    ControllerIF.BranchPredictor ctrl
);

`ifdef USE_GSHARE
    // Gshare is now SMT-aware (duplicated history)
    Gshare predictor( port, next, ctrl );
`else
    // Bimodal is SMT-compatible (shared PHT tables)
    Bimodal predictor( port, next );
`endif

endmodule : BranchPredictor
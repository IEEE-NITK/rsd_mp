#include "../lib.c"   // keep if your build flow expects it

// Memory-mapped UART address used by RSD
#define UART_ADDR ((volatile char*)0x40002000)

/* ------------ basic serial helpers ------------ */

static inline void putc(char c) {
    *UART_ADDR = c;
}

static void puts(const char *s) {
    while (*s) {
        putc(*s++);
    }
}

// print 32-bit value as 8 hex digits
static void print_hex8(unsigned int x) {
    int i;
    for (i = 7; i >= 0; i--) {
        unsigned int nibble = (x >> (i * 4)) & 0xF;
        char c;
        if (nibble < 10) c = '0' + nibble;
        else            c = 'A' + (nibble - 10);
        putc(c);
    }
}

// print array as 8-hex-digits-per-line
static void print_array_hex(const int *a, int n) {
    int i;
    for (i = 0; i < n; i++) {
        print_hex8((unsigned int)a[i]);
        putc('\n');
    }
}

/* ------------ quicksort implementation ------------ */

static void swap(int *a, int *b) {
    int t = *a;
    *a = *b;
    *b = t;
}

// Lomuto partition: pivot = a[right]
static int partition(int *a, int left, int right) {
    int pivot = a[right];
    int i = left - 1;
    int j;

    for (j = left; j < right; j++) {
        if (a[j] <= pivot) {
            i++;
            swap(&a[i], &a[j]);
        }
    }
    swap(&a[i + 1], &a[right]);
    return i + 1;
}

static void quicksort(int *a, int left, int right) {
    if (left >= right) {
        return;
    }

    int p = partition(a, left, right);
    quicksort(a, left, p - 1);
    quicksort(a, p + 1, right);
}

/* ------------ small helper to sanity-check ------------ */

static int is_sorted(const int *a, int n) {
    int i;
    for (i = 1; i < n; i++) {
        if (a[i - 1] > a[i]) return 0;
    }
    return 1;
}

/* ------------ main ------------ */

int main(void) {
    // Feel free to change these values / size
    int arr[] = { 7, 3, 10, 1, 9, 2, 8 };
    int n = sizeof(arr) / sizeof(arr[0]);

    puts("QS full start\n");
    puts("Before:\n");
    print_array_hex(arr, n);

    quicksort(arr, 0, n - 1);

    puts("After:\n");
    print_array_hex(arr, n);

    if (is_sorted(arr, n)) {
        puts("QS OK\n");
    } else {
        puts("QS FAIL\n");
    }

    return 0;
}

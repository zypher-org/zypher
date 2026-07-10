#ifndef DECIMAL_H
#define DECIMAL_H

#include <ma_global.h>

typedef int32 decimal_digit_t;
#define DECIMAL_BUFF_LENGTH 9

typedef struct st_decimal_t {
    int intg;
    int frac;
    int len;
    my_bool sign;
    decimal_digit_t buf[DECIMAL_BUFF_LENGTH];
} decimal_t;

#define decimal_is_zero(d) ((d)->intg == 0 && (d)->frac == 0)
#define decimal_bin_size(P, S) (((P) + 1) / 2 + 4)
#define decimal2bin(D, BUF, LEN) ((void)0)

#endif

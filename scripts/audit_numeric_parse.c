/* Observational probe for IO_REVIEW.md; not an acceptance test suite.
 * Compile with src/smaug_convert.c and -Iinclude, then run from any directory.
 * Optional --null-output-i64 / --null-output-f64 cases run in separate processes.
 */
#include "smaug_convert.h"
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    const char *label;
    const char *source;
    size_t length;
} parse_case_t;

#define PARSE_CASE(label, source) {label, source, sizeof(source) - 1}

int main(int argument_count, char **arguments) {
    if (argument_count == 2) {
        if (strcmp(arguments[1], "--null-output-i64") == 0)
            return smaug_parse_i64("1", 1, NULL);
        if (strcmp(arguments[1], "--null-output-f64") == 0)
            return smaug_parse_f64("1", 1, NULL);
        return 2;
    }

    const parse_case_t cases[] = {
        {"null-input", NULL, 1},
        PARSE_CASE("empty", ""),
        PARSE_CASE("space-only", " "),
        PARSE_CASE("leading-space", " 1"),
        PARSE_CASE("trailing-space", "1 "),
        PARSE_CASE("sign-only", "+"),
        PARSE_CASE("nul-only", "\0"),
        PARSE_CASE("embedded-nul", "123\0abc"),
        PARSE_CASE("final-nul-in-slice", "123\0"),
        PARSE_CASE("float-nul", "1.5\0abc"),
        PARSE_CASE("i64-max", "9223372036854775807"),
        PARSE_CASE("i64-min", "-9223372036854775808"),
        PARSE_CASE("i64-overflow", "9223372036854775808"),
        PARSE_CASE("i64-underflow", "-9223372036854775809"),
        PARSE_CASE("float-overflow", "1e400"),
        PARSE_CASE("float-underflow", "1e-400"),
        PARSE_CASE("minimum-normal", "0x1p-1022"),
        PARSE_CASE("minimum-subnormal-hex", "0x1p-1074"),
        PARSE_CASE("minimum-subnormal-decimal", "4.9406564584124654e-324"),
        PARSE_CASE("negative-zero", "-0.0"),
        PARSE_CASE("nan", "nan"),
        PARSE_CASE("infinity", "inf"),
        PARSE_CASE("incomplete-exponent", "1e"),
        PARSE_CASE("long-one", "1000000000000000000000000000000000000000000000000000000000000000e-63"),
    };
    for (size_t case_index = 0; case_index < sizeof(cases) / sizeof(cases[0]); case_index++) {
        int64_t integer_output = 77;
        double float_output = 77;
        int integer_result = smaug_parse_i64(cases[case_index].source, cases[case_index].length, &integer_output);
        int float_result = smaug_parse_f64(cases[case_index].source, cases[case_index].length, &float_output);
        printf("%s len=%zu | slice i64=%d:%" PRId64 " f64=%d:%a",
               cases[case_index].label, cases[case_index].length,
               integer_result, integer_output, float_result, float_output);
        integer_output = 77;
        float_output = 77;
        integer_result = smaug_parse_i64_cstr(cases[case_index].source, &integer_output);
        float_result = smaug_parse_f64_cstr(cases[case_index].source, &float_output);
        printf(" | cstr i64=%d:%" PRId64 " f64=%d:%a\n", integer_result, integer_output, float_result, float_output);
    }

    char boundary[66];
    memset(boundary, '0', sizeof(boundary));
    for (size_t length = 63; length <= 65; length++) {
        boundary[length - 1] = '1';
        int64_t integer_output = 77;
        double float_output = 77;
        int integer_result = smaug_parse_i64(boundary, length, &integer_output);
        int float_result = smaug_parse_f64(boundary, length, &float_output);
        printf("unterminated-boundary len=%zu | i64=%d:%" PRId64 " f64=%d:%a\n",
               length, integer_result, integer_output, float_result, float_output);
        boundary[length - 1] = '0';
    }
    /* Exact-size source exercises a slice without accessible terminator. */
    const char exact_slice[3] = {'1', '2', '3'};
    int64_t integer_output = 77;
    double float_output = 77;
    int integer_result = smaug_parse_i64(exact_slice, sizeof(exact_slice), &integer_output);
    int float_result = smaug_parse_f64(exact_slice, sizeof(exact_slice), &float_output);
    printf("exact-slice | i64=%d:%" PRId64 " f64=%d:%a\n", integer_result, integer_output, float_result, float_output);
    return 0;
}

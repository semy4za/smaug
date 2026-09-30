/* Probe observacional das políticas ainda em discussão; não é gate de aceitação.
 * Compilar junto dos fontes C conforme docs/IO_REVIEW.md. */
#include "smaug.h"
#include "smaug_io.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void inspect(const char *label, const char *input, size_t length, int json) {
    smaug_table_t *table = json ? smaug_read_json_mem(input, length)
                               : smaug_read_csv_mem(input, length, NULL);
    printf("%s: ", label);
    if (!table) {
        puts("NULL");
        return;
    }
    if (table->error) {
        printf("ERROR %s\n", table->error);
    } else {
        printf("ACCEPT rows=%zu columns=%zu", table->nrows, table->ncols);
        if (table->ncols) {
            printf(" name_hex=");
            for (size_t byte = 0; byte < table->columns[0].name_len; byte++) {
                printf("%02x", (unsigned char)table->columns[0].name[byte]);
            }
        }
        if (table->ncols && table->nrows && table->columns[0].str) {
            size_t value_length;
            const char *value = smaug_str_get(table->columns[0].str, 0, &value_length);
            if (value) {
                printf(" first_value_hex=");
                for (size_t byte = 0; byte < value_length; byte++) {
                    printf("%02x", (unsigned char)value[byte]);
                }
            }
        }
        putchar('\n');
    }
    smaug_table_free(table);
}

int main(void) {
    const struct { const char *label; const char *input; int json; } cases[] = {
        {"JSON continuation isolated", "[{\"v\":\"\x80\"}]", 1},
        {"JSON overlong NUL", "[{\"v\":\"\xc0\x80\"}]", 1},
        {"JSON UTF8 surrogate", "[{\"v\":\"\xed\xa0\x80\"}]", 1},
        {"JSON above U+10FFFF", "[{\"v\":\"\xf4\x90\x80\x80\"}]", 1},
        {"JSON initial BOM", "\xef\xbb\xbf[{\"v\":1}]", 1},
        {"JSON escaped isolated surrogate", "[{\"v\":\"\\ud800\"}]", 1},
        {"CSV short row", "a,b\n1\n", 0},
        {"CSV long row", "a,b\n1,2,3\n", 0},
        {"CSV unclosed quotes", "v\n\"unfinished", 0},
        {"CSV text after closing quote", "v\n\"x\"junk\n", 0},
        {"CSV quote inside unquoted field", "v\nx\"y\n", 0},
        {"CSV raw nonUTF8", "v\n\x80\n", 0},
        {"CSV initial BOM", "\xef\xbb\xbf" "v\n1\n", 0},
        {"CSV bare CR", "v\r1\r", 0},
    };
    for (size_t index = 0; index < sizeof(cases) / sizeof(cases[0]); index++) {
        inspect(cases[index].label, cases[index].input, strlen(cases[index].input),
                cases[index].json);
    }
    const char csv[] = "v\n\x80\n";
    smaug_table_t *table = smaug_read_csv_mem(csv, sizeof(csv) - 1, NULL);
    if (!table || table->error) {
        smaug_table_free(table);
        return 1;
    }
    size_t length = 0;
    char *error = NULL;
    char *output = smaug_write_json_mem(table, NULL, &length, &error);
    printf("JSON writer with invalid UTF8: %s\n", output ? "ACCEPT" : error ? error : "NULL");
    free(output);
    free(error);
    smaug_table_free(table);
    return 0;
}

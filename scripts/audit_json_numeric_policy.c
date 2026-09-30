/* Probe observacional: descreve a árvore atual, não aprova sua política.
   Compilação e interpretação documentadas em docs/IO_REVIEW.md. */
#include "smaug.h"
#include "smaug_io.h"
#include "smaug_convert.h"
#include <inttypes.h>
#include <locale.h>
#include <stdio.h>
#include <string.h>

static const char *status_name(smaug_status_t status) {
    switch (status) {
        case SMG_OK: return "OK";
        case SMG_ERR_SYNTAX: return "SYNTAX";
        case SMG_ERR_OVERFLOW: return "OVERFLOW";
        case SMG_ERR_UNDERFLOW: return "UNDERFLOW";
        case SMG_ERR_NOMEM: return "NOMEM";
        case SMG_ERR_ARGUMENT: return "ARGUMENT";
        default: return "OTHER";
    }
}

static void inspect_json(const char *label, const char *document) {
    printf("%s | %s\n", label, document);
    smaug_table_t *table = smaug_read_json_mem(document, strlen(document));
    if (!table) {
        puts("  NULL");
        return;
    }
    if (table->error) {
        printf("  ERROR: %s\n", table->error);
        smaug_table_free(table);
        return;
    }
    printf("  rows=%zu columns=%zu", table->nrows, table->ncols);
    if (table->ncols == 1) {
        const smaug_column_t *column = &table->columns[0];
        printf(" dtype=%s", column->dtype);
        for (size_t row_index = 0; row_index < table->nrows; row_index++) {
            smaug_status_t status;
            if (column->i64) {
                int64_t value = smaug_i64_get(column->i64, row_index, &status);
                printf(" [%zu]=%s:%" PRId64, row_index, status_name(status), value);
            } else if (column->f64) {
                double value = smaug_f64_get(column->f64, row_index, &status);
                char text[32];
                size_t length = smaug_fmt_f64(text, sizeof(text), value);
                printf(" [%zu]=%s:%s", row_index, status_name(status), length ? text : "FMT_ERROR");
            } else if (column->str) {
                size_t length = 0;
                const char *text = smaug_str_get(column->str, row_index, &length);
                printf(" [%zu]=%s:", row_index, text ? "STRING" : "NULL");
                if (text) {
                    fwrite(text, 1, length, stdout);
                }
            }
        }
    }
    putchar('\n');
    smaug_table_free(table);
}

int main(int argument_count, char **arguments) {
    const char *requested_locale = argument_count > 1 ? arguments[1] : "C";
    if (!setlocale(LC_NUMERIC, requested_locale)) {
        fprintf(stderr, "Locale indisponível: %s\n", requested_locale);
        return 1;
    }
    printf("LC_NUMERIC=%s (observações; saída 0 não aprova a semântica)\n", requested_locale);
    inspect_json("int64 exato", "[{\"v\":9007199254740993}]");
    inspect_json("limite int64", "[{\"v\":9223372036854775807}]");
    inspect_json("fora de int64, exato em f64", "[{\"v\":9223372036854775808}]");
    inspect_json("fora de int64, inexato em f64", "[{\"v\":9223372036854775809}]");
    inspect_json("coluna mista exata", "[{\"v\":42},{\"v\":1.5}]");
    inspect_json("coluna mista inexata", "[{\"v\":9007199254740993},{\"v\":1.5}]");
    inspect_json("representação decimal", "[{\"v\":0.1}]");
    inspect_json("subnormal", "[{\"v\":5e-324}]");
    inspect_json("underflow para zero", "[{\"v\":1e-400}]");
    inspect_json("overflow f64", "[{\"v\":1e400}]");
    inspect_json("texto explícito", "[{\"v\":\"9223372036854775809\"}]");
    inspect_json("zero inicial", "[{\"v\":01}]");
    char long_document[96];
    memcpy(long_document, "[{\"v\":1", 7);
    memset(long_document + 7, '0', 63);
    memcpy(long_document + 70, "e-63}]", 7);
    inspect_json("token longo, valor matemático 1", long_document);
    const char *tokens[] = {"9223372036854775809", "5e-324", "1e-400", "1e400"};
    for (size_t token_index = 0; token_index < sizeof(tokens) / sizeof(tokens[0]); token_index++) {
        int64_t integer_value = 77;
        double real_value = 77.0;
        smaug_status_t integer_status = smaug_parse_i64_cstr_status(tokens[token_index], &integer_value);
        smaug_status_t real_status = smaug_parse_f64_cstr_status(tokens[token_index], &real_value);
        char text[32];
        size_t length = smaug_fmt_f64(text, sizeof(text), real_value);
        printf("core %s | i64=%s:%" PRId64 " f64=%s:%s\n", tokens[token_index],
               status_name(integer_status), integer_value, status_name(real_status),
               length ? text : "FMT_ERROR");
    }
    return 0;
}

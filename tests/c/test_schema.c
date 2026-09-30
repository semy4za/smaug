#include "smaug_io.h"
#include "smaug_core.h"
#include "smaug_string.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static unsigned checks = 0;
static unsigned failures = 0;
#define CHECK(condition, message) do { \
    checks++; \
    if (!(condition)) { fprintf(stderr, "FAIL: %s\n", message); failures++; } \
} while (0)

static smaug_schema_field_t fields[] = {
    {"code", 4, SMAUG_DTYPE_STRING, 0},
    {"quantity", 8, SMAUG_DTYPE_INT64, 1},
    {"active", 6, SMAUG_DTYPE_BOOL, 1},
    {"price", 5, SMAUG_DTYPE_FLOAT64, 1}
};
static const smaug_schema_t schema = {fields, 4};

static void expect_error(smaug_table_t *table, const char *reason) {
    CHECK(table && table->error && strstr(table->error, reason), reason);
    CHECK(!table || (table->ncols == 0 && table->nrows == 0 && !table->columns),
          "schema failure does not publish partial data");
    smaug_table_free(table);
}

static int valid_table(smaug_table_t *table, size_t rows) {
    CHECK(table && !table->error, "schema valid input succeeds");
    if (!table || table->error) {
        if (table && table->error) {
            fprintf(stderr, "%s\n", table->error);
        }
        smaug_table_free(table);
        return 0;
    }
    CHECK(table->nrows == rows && table->ncols == 4, "schema determines shape");
    if (table->ncols != 4 || !table->columns) {
        smaug_table_free(table);
        return 0;
    }
    for (size_t field = 0; field < 4; field++) {
        CHECK(table->columns[field].name_len == fields[field].name_len &&
              memcmp(table->columns[field].name, fields[field].name, fields[field].name_len) == 0,
              "schema determines output order");
    }
    CHECK(table->columns[0].str && table->columns[1].i64 && table->columns[2].boolcol &&
          table->columns[3].f64, "schema preserves all four types");
    return 1;
}

static void test_validation(void) {
    size_t error_field = 77;
    CHECK(smaug_schema_validate(&schema, &error_field) == SMG_OK && error_field == SIZE_MAX,
          "valid schema descriptor");
    CHECK(smaug_schema_validate(NULL, &error_field) == SMG_ERR_ARGUMENT &&
          error_field == SIZE_MAX, "NULL schema descriptor");
    smaug_schema_t invalid = {NULL, 1};
    CHECK(smaug_schema_validate(&invalid, NULL) == SMG_ERR_ARGUMENT, "NULL fields");
    invalid.fields = fields;
    invalid.count = SIZE_MAX;
    CHECK(smaug_schema_validate(&invalid, NULL) == SMG_ERR_OVERFLOW, "schema count overflow");
    invalid.count = 0;
    CHECK(smaug_schema_validate(&invalid, NULL) == SMG_ERR_ARGUMENT, "empty schema");
    smaug_schema_field_t local_fields[] = {{"", 0, SMAUG_DTYPE_INT64, 0},
                                          {"x\0tail", 6, SMAUG_DTYPE_BOOL, 1}};
    invalid.fields = local_fields;
    invalid.count = 2;
    CHECK(smaug_schema_validate(&invalid, NULL) == SMG_OK, "empty and NUL names accepted");
    local_fields[1] = local_fields[0];
    CHECK(smaug_schema_validate(&invalid, &error_field) == SMG_ERR_ARGUMENT && error_field == 1,
          "duplicate schema name rejected");
    invalid.count = 1;
    local_fields[0].name = NULL;
    CHECK(smaug_schema_validate(&invalid, NULL) == SMG_ERR_ARGUMENT, "NULL name rejected");
    local_fields[0].name = "";
    local_fields[0].name_len = SIZE_MAX;
    CHECK(smaug_schema_validate(&invalid, NULL) == SMG_ERR_OVERFLOW, "name size overflow");
    local_fields[0].name_len = 0;
    local_fields[0].nullable = 2;
    CHECK(smaug_schema_validate(&invalid, NULL) == SMG_ERR_ARGUMENT, "invalid nullable rejected");
    local_fields[0].nullable = 0;
    local_fields[0].dtype = (smaug_dtype_t)99;
    CHECK(smaug_schema_validate(&invalid, NULL) == SMG_ERR_ARGUMENT, "invalid dtype rejected");
    expect_error(smaug_read_csv_mem_schema("bad", 3, NULL, NULL), "invalid schema");
    expect_error(smaug_read_json_mem_schema("bad", 3, NULL), "invalid schema");
    expect_error(smaug_read_csv_mem_schema(NULL, 1, NULL, &schema), "NULL buffer");
    expect_error(smaug_read_json_mem_schema(NULL, 1, &schema), "NULL buffer");
}

static void test_csv(void) {
    const char *document = "price,active,quantity,code\n1.5,false,9223372036854775807,00123\n"
                           ",,,00234\n";
    smaug_table_t *table = smaug_read_csv_mem_schema(document, strlen(document), NULL, &schema);
    if (valid_table(table, 2)) {
        size_t length;
        const char *value = smaug_str_get(table->columns[0].str, 0, &length);
        CHECK(value && length == 5 && memcmp(value, "00123", 5) == 0,
              "schema CSV keeps leading zeros");
        smaug_status_t status;
        CHECK(smaug_i64_get(table->columns[1].i64, 0, &status) == INT64_MAX && status == SMG_OK,
              "schema CSV keeps exact int64");
        CHECK(smaug_bool_get(table->columns[2].boolcol, 0, &status) == 0 && status == SMG_OK,
              "schema CSV preserves false");
        CHECK(smaug_f64_get(table->columns[3].f64, 0, &status) == 1.5 && status == SMG_OK,
              "schema CSV preserves float");
        smaug_i64_get(table->columns[1].i64, 1, &status);
        CHECK(status == SMG_NULL_VALUE, "schema CSV explicit empty is NA");
        smaug_table_free(table);
    }
    const char *header = "code,quantity,active,price\n";
    table = smaug_read_csv_mem_schema(header, strlen(header), NULL, &schema);
    if (valid_table(table, 0)) {
        smaug_table_free(table);
    }
    smaug_csv_opts_t options = smaug_csv_default_opts();
    options.header = 0;
    options.sep = ';';
    options.decimal = ',';
    document = "00123;42;true;2,5";
    table = smaug_read_csv_mem_schema(document, strlen(document), &options, &schema);
    if (valid_table(table, 1)) {
        smaug_status_t status;
        CHECK(smaug_f64_get(table->columns[3].f64, 0, &status) == 2.5 && status == SMG_OK,
              "schema CSV decimal option");
        smaug_table_free(table);
    }
    const char *bad_documents[] = {
        "code,quantity,active,price\nx,bad,true,1\n",
        "code,quantity,active,price\nx,9223372036854775808,true,1\n",
        "code,quantity,active,price\nx,1,maybe,1\n",
        "code,quantity,active,price\nx,1,true,1e9999\n",
        "code,quantity,active,price\nx,1,true,1e-9999\n",
        "code,quantity,active,price\n,1,true,1\n",
        "code,quantity,active,price\nx,1,true\n",
        "code,quantity,active,extra\nx,1,true,1\n",
        "code,quantity,active,code\nx,1,true,1\n",
        "code,quantity\nx,1\n"
    };
    const char *reasons[] = {"SYNTAX", "OVERFLOW", "SYNTAX", "OVERFLOW", "UNDERFLOW",
                             "non-nullable", "largura", "unknown", "duplicate", "width"};
    for (size_t test = 0; test < sizeof(reasons) / sizeof(*reasons); test++) {
        expect_error(smaug_read_csv_mem_schema(bad_documents[test], strlen(bad_documents[test]),
                                               NULL, &schema), reasons[test]);
    }
    expect_error(smaug_read_csv_mem_schema("", 0, NULL, &schema), "entrada vazia");
}

static void test_json(void) {
    const char *document = "[{\"price\":1.5,\"quantity\":9223372036854775807,"
                           "\"active\":false,\"code\":\"00123\"},{\"code\":\"00234\"}]";
    smaug_table_t *table = smaug_read_json_mem_schema(document, strlen(document), &schema);
    if (valid_table(table, 2)) {
        smaug_status_t status;
        CHECK(smaug_i64_get(table->columns[1].i64, 0, &status) == INT64_MAX && status == SMG_OK,
              "schema JSON keeps exact int64");
        CHECK(smaug_bool_get(table->columns[2].boolcol, 0, &status) == 0 && status == SMG_OK,
              "schema JSON preserves false");
        CHECK(smaug_f64_get(table->columns[3].f64, 0, &status) == 1.5 && status == SMG_OK,
              "schema JSON matches names instead of positions");
        smaug_i64_get(table->columns[1].i64, 1, &status);
        CHECK(status == SMG_NULL_VALUE, "schema JSON missing nullable field is NA");
        smaug_table_free(table);
    }
    table = smaug_read_json_mem_schema("[]", 2, &schema);
    if (valid_table(table, 0)) {
        smaug_table_free(table);
    }
    const char *documents[] = {
        "[{\"code\":\"x\",\"quantity\":\"123\"}]",
        "[{\"code\":\"x\",\"quantity\":1.0}]",
        "[{\"code\":\"x\",\"quantity\":true}]",
        "[{\"code\":\"x\",\"active\":1}]",
        "[{\"code\":123}]",
        "[{\"code\":\"x\",\"price\":9007199254740993}]",
        "[{\"code\":null}]", "[{}]",
        "[{\"code\":\"x\",\"extra\":0}]",
        "[{\"code\":\"x\",\"code\":\"y\"}]"
    };
    const char *reasons[] = {"family", "family", "family", "family", "family",
                             "PRECISION", "non-nullable", "non-nullable", "unknown", "duplicate"};
    for (size_t test = 0; test < sizeof(reasons) / sizeof(*reasons); test++) {
        expect_error(smaug_read_json_mem_schema(documents[test], strlen(documents[test]), &schema),
                     reasons[test]);
    }
    document = "[{\"code\":\"x\",\"price\":9007199254740994}]";
    table = smaug_read_json_mem_schema(document, strlen(document), &schema);
    if (valid_table(table, 1)) {
        smaug_status_t status;
        CHECK(smaug_f64_get(table->columns[3].f64, 0, &status) == 9007199254740994.0 &&
              status == SMG_OK, "schema JSON accepts exact integer above 2^53");
        smaug_table_free(table);
    }
}

static void test_bytes_and_ownership(void) {
    char name[] = "id\0tail";
    smaug_schema_field_t field = {name, 7, SMAUG_DTYPE_STRING, 0};
    smaug_schema_t local_schema = {&field, 1};
    const char csv[] = "id\0tail\n001\0tail\n";
    smaug_table_t *table = smaug_read_csv_mem_schema(csv, sizeof(csv) - 1, NULL, &local_schema);
    CHECK(table && !table->error, "schema CSV accepts NUL name/value");
    if (table && !table->error) {
        name[0] = 'X';
        size_t length;
        const char *value = smaug_str_get(table->columns[0].str, 0, &length);
        CHECK(table->columns[0].name_len == 7 &&
              memcmp(table->columns[0].name, "id\0tail", 7) == 0,
              "schema result owns names independently");
        CHECK(value && length == 8 && memcmp(value, "001\0tail", 8) == 0,
              "schema CSV preserves NUL bytes");
        name[0] = 'i';
    }
    smaug_table_free(table);
    const char *json = "[{\"id\\u0000tail\":\"001\\u0000tail\"}]";
    table = smaug_read_json_mem_schema(json, strlen(json), &local_schema);
    CHECK(table && !table->error, "schema JSON accepts NUL name/value");
    if (table && !table->error) {
        size_t length;
        const char *value = smaug_str_get(table->columns[0].str, 0, &length);
        CHECK(value && length == 8 && memcmp(value, "001\0tail", 8) == 0,
              "schema JSON preserves NUL bytes");
    }
    smaug_table_free(table);
    field.name = "\x80";
    field.name_len = 1;
    expect_error(smaug_read_json_mem_schema("[]", 2, &local_schema), "UTF-8");
    expect_error(smaug_read_csv_schema(NULL, NULL, &schema), "path");
    expect_error(smaug_read_json_schema(NULL, &schema), "path");
    expect_error(smaug_read_csv_schema("/nonexistent/smaug.csv", NULL, &schema), "open");
    expect_error(smaug_read_json_schema("/nonexistent/smaug.json", &schema), "open");
#ifdef __linux__
    expect_error(smaug_read_json_schema("/tmp", &schema), "read failed");
#endif
}

int main(void) {
    test_validation();
    test_csv();
    test_json();
    test_bytes_and_ownership();
    printf("%s: schema (%u checks)\n", failures ? "FAIL" : "PASS", checks);
    return failures ? 1 : 0;
}

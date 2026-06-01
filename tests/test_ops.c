#include "../include/smaug.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

#define EQ(a,b) (fabs((a)-(b)) < 1e-9)

int main(void) {
    smaug_series_f64_t *s = smaug_f64_create(5);
    for (size_t i = 0; i < 5; i++) smaug_f64_set(s, i, (double)(i+1)*10);
    assert(EQ(smaug_f64_sum(s, true), 150.0));
    assert(EQ(smaug_f64_mean(s, true), 30.0));
    assert(EQ(smaug_f64_min(s, true), 10.0));
    assert(EQ(smaug_f64_max(s, true), 50.0));

    smaug_f64_set_null(s, 2);
    assert(smaug_f64_is_null(s, 2));
    assert(smaug_f64_count_nonnull(s) == 4);

    smaug_f64_free(s);
    printf("PASS\n");
    return 0;
}
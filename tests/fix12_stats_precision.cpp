// fix12: StatsAccumulator must keep the standard deviation of a feature with a large mean and
// a small spread. Compares it with an exact two-pass reference on 50000 samples of a
// height-like value (mean 1.6, spread +-0.01). Built and run by tests/run_tests.sh against
// the src/ folder it is given (-I <src>).
#include "math/stats.hpp"

#include <cstdio>

static float sample(int i) {
    return 1.6f + 0.01f * std::sin(i * 0.37f);
}

int main() {
    const int count = 50000;
    StatsAccumulator accumulator;
    long double sum = 0;
    for (int i = 0; i < count; i++) {
        accumulator.add_sample(sample(i));
        sum += sample(i);
    }
    const long double mean = sum / count;
    long double squares = 0;
    for (int i = 0; i < count; i++) {
        squares += (sample(i) - mean) * (sample(i) - mean);
    }
    const double reference = std::sqrt(static_cast<double>(squares / count));
    const double measured = accumulator.get_standard_deviation();
    const double error = std::fabs(measured - reference) / reference * 100.0;
    std::printf("RESULT fix12_stats_precision %s reference_std=%.7f accumulator_std=%.7f error=%.3f%% (limit 0.1%%)\n",
                error < 0.1 ? "PASS" : "FAIL", reference, measured, error);
    return error < 0.1 ? 0 : 1;
}

#pragma once

#include <algorithm>
#include <cfloat>
#include <cmath>

class StatsAccumulator {
private:
    // Double precision: the variance is a difference of two large sums and
    // loses most of its digits in float over thousands of poses.
    double sum;
    double sum_of_squares;
    float max_value;
    float min_value;
    int count;

public:
    StatsAccumulator()
        : sum(0.0f), sum_of_squares(0.0f), max_value(-INFINITY), min_value(INFINITY), count(0) {
    }

    void add_sample(float sample) {
        sum += sample;
        sum_of_squares += static_cast<double>(sample) * sample;
        max_value = std::max(max_value, sample);
        min_value = std::min(min_value, sample);
        count++;
    }

    float get_mean() const {
        return static_cast<float>(sum / count);
    }

    float get_max() const {
        return max_value;
    }

    float get_min() const {
        return min_value;
    }

    float get_standard_deviation() const {
        const double mean = sum / count;
        const double variance = (sum_of_squares / count) - (mean * mean);
        if (variance < FLT_EPSILON) {
            return 0.0f;
        }
        return static_cast<float>(sqrt(variance));
    }

    void reset() {
        sum = 0.0f;
        sum_of_squares = 0.0f;
        max_value = -INFINITY;
        min_value = INFINITY;
        count = 0;
    }
};

float distance_squared(const float* a, const float* b, int dim) {
    float distance = 0.0f;
    for (int i = 0; i < dim; i++) {
        const float diff = a[i] - b[i];
        distance += diff * diff;
    }
    return distance;
}
#include "frequency.h"

int check_outliers(uint32_t curr_freq, uint32_t incoming_freq) {
	uint32_t difference = incoming_freq > curr_freq ? incoming_freq - curr_freq: curr_freq - incoming_freq;
	float average = (incoming_freq + curr_freq) / 2.0;
	float percent_difference = (difference / average) * 100.0;
	if (percent_difference > OUTLIER_THRESHOLD) {
	    return 1;
	} else {
		return 0;
	}
}



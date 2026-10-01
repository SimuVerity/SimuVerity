/*
 * calc.h
 *
 *  Created on: Apr 21, 2023
 *      Author: ProfessorG
 */

#ifndef INC_CALC_H_
#define INC_CALC_H_

#include <stdint.h>
#include <math.h>

#define MAX_THROTTLE_PERCENT 80

typedef struct {
  float left;
  float right;
} throttle_percents;

float convert_throttle_input(uint16_t raw);
float convert_steering_wheel_angle(uint16_t raw);
float steering_wheel_angle_to_steering_angle(float steering_wheel_angle);
float convert_rpm(uint16_t raw);
throttle_percents convert_power_ratio(float ratio, float throttle_in);
throttle_percents throttle_percent(throttle_percents throttle, float throttle_in);

#endif /* INC_CALC_H_ */

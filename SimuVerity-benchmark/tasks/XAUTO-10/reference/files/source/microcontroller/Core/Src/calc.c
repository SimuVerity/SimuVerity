/*
 * calc.c
 *
 *  Created on: Apr 27, 2023
 *      Author: ProfessorG
 */

#include "calc.h"

// steering wheel angle [0, 4096) => [-230deg, 230deg)
float convert_steering_wheel_angle(uint16_t raw)
{
  float val = (float)raw;
  val /= 4096.0;
  val -= 0.5;
  val *= 2.0*230.0*M_PI/180.0;
  return val;
}

float steering_wheel_angle_to_steering_angle(float steering_wheel_angle)
{ // y = (8.355*10^ -5)x^2 + 0.139x - 0.03133
	float x = steering_wheel_angle;
	return (8.355E-5)*x*x + 0.139*x - 0.03133;
}

float convert_throttle_input(uint16_t raw)
{
  float val = (float)raw;
  val /= 4095.0;
  val *= 100.0;
  return val;
}

float convert_rpm(uint16_t raw) {
	float val = (float)raw;
	val /= 4.0;
	val = 18 * M_PI * 60 / 63360;
	return val;
}

throttle_percents convert_power_ratio(float ratio, float throttle_in)
{
  float r, ti;
  r = ratio/100.0;
  ti = throttle_in/100.0;

  throttle_percents out = (throttle_percents){
    .left  = ti*r*100.0,
    .right = ti*(1.0-r)*100.0,
  };

  return out;
}

throttle_percents throttle_percent(throttle_percents throttle, float throttle_in)
{
	throttle_percents out;
	float ti = throttle_in/100.0;
	out.left  = throttle.left  * ti;
	out.right = throttle.right * ti;
	return out;
}


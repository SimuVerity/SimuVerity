use pid::calc;
use std::f32::consts;

const ERROR: f32 = 0.5;
const T: f32 = 70.0;
const PREV_ERROR: f32 = 0.3;
const VX: f32 = 10.0;
const ST: f32 = 50.0;
const MAX_T: f32 = 80.0;

#[test]
fn test_p() {
    assert_eq!(calc::p(ERROR), calc::POR * ERROR);
}

#[test]
fn test_i() {
    assert_eq!(calc::i(ERROR, T), calc::INT * ERROR * T);
}

#[test]
fn test_d() {
    assert_eq!(calc::d(ERROR, T, PREV_ERROR), calc::DER * (ERROR * PREV_ERROR) / T);
}

#[test]
fn test_radians_to_ms() {
    assert_eq!(calc::radians_to_ms(20.0), 20.0 * calc::WHEEL_RADIUS);
}

#[test]
fn test_degrees_to_radians() {
    assert_eq!(calc::degrees_to_radians(50.0), 50.0 * (consts::PI / 180.0));
}

#[test]
fn test_calculate_desired_yaw_rate() {
    assert_eq!(calc::calculate_desired_yaw_rate(VX, ST), (VX / ((calc::LF + calc::LR) + (0.0012965 * VX.powf(2.0)))) * ST);
}

#[test]
fn test_calculate_yaw_rate() {
    let mut ku: f32 = 5.0;
    ku += ((((-calc::LF * calc::CY_F + calc::LR * calc::CY_R) / (calc::IZZ * VX)) - ((calc::LF.powf(2.0) * calc::CY_F + calc::LR.powf(2.0) * calc::CY_R) / (calc::IZZ * VX))) * 5.0 + ((calc::LF * calc::CY_F) / calc::IZZ) * ST + (1.0 / (0.05 * calc::IZZ)) * calc::calculate_delta_torque(20.0, 60.0)) / T;
    assert_eq!(calc::calculate_yaw_rate(T, 5.0, VX, ST, 20.0, 60.0), ku);
}

#[test]
fn test_calculate_yaw_moment() {
    assert_eq!(calc::calculate_yaw_moment(20.0, 60.0), (20.0 - 60.0) * calc::TR);
}

#[test]
fn test_calculate_lateral_velocity() {
    assert_eq!(calc::calculate_lateral_velocity(VX, ST), ((-(calc::CY_F + calc::CY_R)/(calc::M * VX)) + (((-calc::LF * calc::CY_F + calc::LR + calc::CY_R)/(calc::M * VX)) - VX)) + (calc::CY_F / (calc::M * VX)) * ST);
}

#[test]
fn test_calculate_delta_torque() {
    assert_eq!(calc::calculate_delta_torque(20.0, 60.0), (calc::RW / (2.0 * calc::TR * calc::GR)) * calc::calculate_yaw_moment(20.0, 60.0));
}

#[test]
fn test_magic_formula() {
    let p: f32 = 1.02 - 1.0;
    assert_eq!(calc::magic_formula(calc::WEIGHT, 1.02), calc::WEIGHT * calc::D * f32::sin(calc::C * f32::atan(calc::B * p * (1.0 - calc::E) + calc::E * calc::B * p - f32::atan(calc::B * p))));
}

#[test]
fn test_steering_wheel_angle_to_steering_angle() {
    let mut x: f32 = 8.355 * 10_f32.powf(-5.0) * ST.powi(2) + 0.139 * ST - 0.03133;
    x = calc::degrees_to_radians(x);
    assert_eq!(calc::steering_wheel_angle_to_steering_angle(ST), x);
}

#[test]
fn test_calculate_power_ratio() {
    let mut ratio: f32 = ERROR;
    ratio += calc::p(ERROR) + calc::i(ERROR, T) + calc::d(ERROR, T, PREV_ERROR);
    if ratio > 1.0 {
        ratio = 1.0;
    } if ratio < 0.0 {
        ratio = 0.0;
    }
    let rl_torque: f32 = ratio * MAX_T;
    let rr_torque: f32 = (1.0 - ratio) * MAX_T;
    assert_eq!(calc::calculate_power_ratio(ERROR, PREV_ERROR, T, MAX_T), (rl_torque, rr_torque)); 
}
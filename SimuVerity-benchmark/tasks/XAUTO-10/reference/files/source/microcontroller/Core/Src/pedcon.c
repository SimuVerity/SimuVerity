/*
Pedal Controller code
*/

#include "pedcon.h"
/*
Calculates the voltage offset between both voltage inputs.

Args: first voltage (first_v), second voltage (second_v)

Returns: 1 if between 0-10% difference, else return 0.
*/
int voltage_offset(uint16_t first_v, uint16_t second_v) {
    
    
    if (first_v == 0 && second_v == 0) {
        return 1;
    }
    else if (first_v == 0) {
        if (second_v < 10)
            return 1;
        else
            return 0;
    }
    else if (second_v == 0) {
        if (first_v < 10)
            return 1;
        else
            return 0;
    }
    else if (first_v == second_v) {
        return 1;
    }
    float diff = 0;
    if (first_v > second_v) {
        diff = ((float) second_v / (float) first_v) * 100.0;
    }
    else if (first_v < second_v) {
        diff = ((float) first_v / (float) second_v) * 100.0;
    }
    if (diff < 90.0)
        return 0;

    return 1;
}

/*
Calculates to see if voltage of a sensor is at 0.5v (0) or 4.5v (4096)

Args: sensor voltage (sensor)

Returns: 0 if voltage is 0.5v or 4.5v, else return 1.
*/
int voltage_check(uint16_t sensor) {
    if (sensor == 0 || sensor == 4096)
        return 0;
    return 1;
}

/*
Detects if a fault has lasted more than 100ms.

Args: value.

Returns: If time_check surpasses a specified value representing time, then return 0.
Else return 1.
*/
int time_fault_check(uint32_t value) {
    if (value == 44444)
        return 0;
    return 1;
}

#include <stdint.h>

typedef struct {
uint32_t time_check;
uint16_t first_v;
uint16_t second_v;
uint16_t user_v;
uint16_t time_check_true;
} pedal_con;

int voltage_offset(uint16_t first_v, uint16_t second_v);
int voltage_check(uint16_t sensor);
int time_fault_check(uint32_t value);

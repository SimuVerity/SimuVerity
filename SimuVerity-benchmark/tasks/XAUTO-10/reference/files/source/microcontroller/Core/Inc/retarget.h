// All credit to Carmine Noviello for this code
// https://github.com/cnoviello/mastering-stm32/blob/master/nucleo-f030R8/system/include/retarget/retarget.h

#ifndef _RETARGET_H__
#define _RETARGET_H__

#include "stm32f4xx_hal.h"
#include <sys/stat.h>

void RetargetInit(UART_HandleTypeDef *huart);
int _write(int fd, char* ptr, int len);
int _read(int fd, char* ptr, int len);

#endif //#ifndef _RETARGET_H__

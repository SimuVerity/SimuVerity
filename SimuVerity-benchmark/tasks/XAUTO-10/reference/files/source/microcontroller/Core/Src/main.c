/* USER CODE BEGIN Header */
/**
 ******************************************************************************
 * @file           : main.c
 * @brief          : Main program body
 ******************************************************************************
 * @attention
 *
 * Copyright (c) 2023 STMicroelectronics.
 * All rights reserved.
 *
 * This software is licensed under terms that can be found in the LICENSE file
 * in the root directory of this software component.
 * If no LICENSE file comes with this software, it is provided AS-IS.
 *
 ******************************************************************************
 */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "fatfs.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "pedcon.h"
#include "frequency.h"
#include "comm.h"
#include "sdlog.h"
#include "calc.h"
#include "retarget.h"
#include "lut.h"
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/
ADC_HandleTypeDef hadc1;
ADC_HandleTypeDef hadc2;
ADC_HandleTypeDef hadc3;

CAN_HandleTypeDef hcan1;

DAC_HandleTypeDef hdac;

SPI_HandleTypeDef hspi1;

TIM_HandleTypeDef htim2;
TIM_HandleTypeDef htim5;

UART_HandleTypeDef huart2;

/* USER CODE BEGIN PV */
CAN_RxHeaderTypeDef rxHeader; //CAN Bus Transmit Header
CAN_TxHeaderTypeDef txHeader; //CAN Bus Receive Header
uint8_t canRX[6];  //CAN Bus Receive Buffer
CAN_FilterTypeDef canfil; //CAN Bus Filter
CAN_FilterTypeDef canfil1; //CAN Bus Filter
CAN_FilterTypeDef canfil2; //CAN Bus Filter
CAN_FilterTypeDef canfil3; //CAN Bus Filter
uint32_t canMailbox; //CAN Bus Mail box variable

int loop;
uint16_t voltage;
uint16_t RPM;
uint16_t current;
uint16_t power;
/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
static void MX_GPIO_Init(void);
static void MX_ADC1_Init(void);
static void MX_CAN1_Init(void);
static void MX_DAC_Init(void);
static void MX_TIM2_Init(void);
static void MX_TIM5_Init(void);
static void MX_ADC2_Init(void);
static void MX_ADC3_Init(void);
static void MX_USART2_UART_Init(void);
static void MX_SPI1_Init(void);
/* USER CODE BEGIN PFP */
//SD Card Globals
FRESULT file_res;
char *file_name = NULL;
short int detect = 0;
short int detect_last = 0;
int file_length = 0;
char buffer[100];
int file_index = 0;
/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */
pedal_con pedal;
frequency_data tim2;
frequency_data tim5;
throttle_percents throttle;
/* USER CODE END 0 */

/**
  * @brief  The application entry point.
  * @retval int
  */
int main(void)
{
  /* USER CODE BEGIN 1 */
	/*pedal_con pedal;
	 pedal.first_v = 0;
	 pedal.second_v = 0;
	 pedal.user_v = 0;*/

  /* USER CODE END 1 */

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick. */
  HAL_Init();

  /* USER CODE BEGIN Init */

  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* USER CODE BEGIN SysInit */
	canfil.FilterMode = CAN_FILTERMODE_IDMASK;
	  canfil.FilterFIFOAssignment = CAN_RX_FIFO0;
	  canfil.FilterIdHigh = 0x0A5<<5;
	  canfil.FilterIdLow = 0;
	  canfil.FilterMaskIdHigh = 0xFFFF;
	  canfil.FilterMaskIdLow = 0;
	  canfil.FilterScale = CAN_FILTERSCALE_32BIT;
	  canfil.FilterActivation = ENABLE;

		canfil1.FilterBank = 1;
	  canfil1.FilterMode = CAN_FILTERMODE_IDMASK;
	  canfil1.FilterFIFOAssignment = CAN_RX_FIFO0;
	  canfil1.FilterIdHigh = 0x0A6<<5;
	  canfil1.FilterIdLow = 0;
	  canfil1.FilterMaskIdHigh = 0xFFFF;
	  canfil1.FilterMaskIdLow = 0;
	  canfil1.FilterScale = CAN_FILTERSCALE_32BIT;
	  canfil1.FilterActivation = ENABLE;

		canfil2.FilterBank = 2;
	  canfil2.FilterMode = CAN_FILTERMODE_IDMASK;
	  canfil2.FilterFIFOAssignment = CAN_RX_FIFO0;
	  canfil2.FilterIdHigh = 0x0A7<<5;
	  canfil2.FilterIdLow = 0;
	  canfil2.FilterMaskIdHigh = 0xFFFF;
	  canfil2.FilterMaskIdLow = 0;
	  canfil2.FilterScale = CAN_FILTERSCALE_32BIT;
	  canfil2.FilterActivation = ENABLE;

		canfil3.FilterBank = 3;
	  canfil3.FilterMode = CAN_FILTERMODE_IDMASK;
	  canfil3.FilterFIFOAssignment = CAN_RX_FIFO0;
	  canfil3.FilterIdHigh = 0x0AA<<5;
	  canfil3.FilterIdLow = 0;
	  canfil3.FilterMaskIdHigh = 0xFFFF;
	  canfil3.FilterMaskIdLow = 0;
	  canfil3.FilterScale = CAN_FILTERSCALE_32BIT;
	  canfil3.FilterActivation = ENABLE;


	  txHeader.DLC = 8;
	  txHeader.IDE = CAN_ID_STD;
	  txHeader.RTR = CAN_RTR_DATA;
	  txHeader.StdId = 0x103;
	  txHeader.ExtId = 0x02;
	  txHeader.TransmitGlobalTime = DISABLE;

	  HAL_CAN_ConfigFilter(&hcan1,&canfil);
	  HAL_CAN_ConfigFilter(&hcan1,&canfil1);
	  HAL_CAN_ConfigFilter(&hcan1,&canfil2);
	  HAL_CAN_ConfigFilter(&hcan1,&canfil3);

	  HAL_CAN_Start(&hcan1);
	  HAL_CAN_ActivateNotification(&hcan1,CAN_IT_RX_FIFO0_MSG_PENDING);
	  RetargetInit(&huart2);
  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_ADC1_Init();
  MX_CAN1_Init();
  MX_DAC_Init();
  MX_TIM2_Init();
  MX_TIM5_Init();
  MX_ADC2_Init();
  MX_ADC3_Init();
  MX_USART2_UART_Init();
  MX_SPI1_Init();
  MX_FATFS_Init();
  /* USER CODE BEGIN 2 */
	HAL_TIM_IC_Start_IT(&htim2, TIM_CHANNEL_1);
	HAL_TIM_IC_Start_IT(&htim5, TIM_CHANNEL_2);
	HAL_ADC_Start_IT(&hadc1);
	HAL_ADC_Start_IT(&hadc2);
	HAL_ADC_Start_IT(&hadc3);
	HAL_DAC_Start(&hdac, 1);
	HAL_DAC_Start(&hdac, 2);
	HAL_CAN_Start(&hcan1);
	htim2.Channel = HAL_TIM_ACTIVE_CHANNEL_1;
	htim5.Channel = HAL_TIM_ACTIVE_CHANNEL_2;

	if (sd_mount("/") == FR_OK)
		//SD card detected
		detect = 1;
	else
		//SD card not detected
		detect = 0;
	sd_unmount("/");

  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
	while (1) {
		tim2.CalculationOK = 0;
		tim5.CalculationOK = 0;
		if (!voltage_offset(pedal.first_v, pedal.second_v)
				|| !voltage_check(pedal.user_v)) {
			if (pedal.time_check < 44444) {
				pedal.time_check += 1;
			}
		} else {
			if (HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_7)) {
				HAL_GPIO_TogglePin(GPIOC, GPIO_PIN_7); //Turn off APPS if already active
			}
			if (pedal.time_check > 0) {
				pedal.time_check -= 1;
				pedal.time_check_true = 0;
			}
			if (pedal.time_check == 0) {
				pedal.time_check_true = 1;
			}
		}

		if (time_fault_check(pedal.time_check) && pedal.time_check_true) {
			throttle = lookup_linear(get_steering_angle_smooth(), convert_rpm(RPM));
			throttle = throttle_percent(throttle, get_throttle_in_smooth());
			write_throttle_out(throttle, hdac);
			// Do torque vectoring
		} else {
			throttle.left = 0;
			throttle.right = 0;
			write_throttle_out(throttle, hdac);
			if (!HAL_GPIO_ReadPin(GPIOC, GPIO_PIN_7)) {
				HAL_GPIO_TogglePin(GPIOC, GPIO_PIN_7);
			}
			if (time_fault_check(pedal.time_check)) {
				pedal.time_check_true = 1;
			}
		}

		// Write out to SD card

		//SD Logging:
		/*if(HAL_GPIO_ReadPin(GPIOB, GPIO_PIN_6)){
		 sd_unmount("/");
		 file_res = sd_mount("/");
		 if(file_res == FR_OK){
		 detect = 1;
		 if(detect_last == 0 && detect == 1 || !file_name){
		 //Create a new file
		 //With Headers:
		 //sprintf(<header1>, "<type>", <header_value>)
		 //file_length = strlen(header1) + ... + strlen(headerN);
		 //file_name = (char *) malloc (file_length * sizeof(char))
		 //snprintf(file_name, file_length, "<type1> - ... - <typeN>", <value1>, ... , <valueN>);
		 //sd_format();
		 //file_res = file_create(file_name);
		 //sd_unmount("/");
		 //csv_header(file_name, file_length);
		 //detect_last = detect;
		 }
		 //Turn on LED
		 //HAL_GPIO_WritePin(GPIO pin, function, 1)
		 csv_update(file_name, file_length);
		 file_index++;
		 } else{
		 if(file_name){
		 free(file_name);
		 file_name = NULL;
		 }
		 detect = 0;
		 //Turn LED off when not detected
		 //HAL_GPIO_WritePin(GPIO pin, function, 0)
		 detect_last = detect;
		 }
		 } else {
		 if(file_name){
		 free(file_name);
		 file_name = NULL;
		 }
		 detect = 0;
		 //Turn LED off when not detected
		 //HAL_GPIO_WritePin(GPIO pin, function, 0)

		 detect_last = detect;

		 }*/

    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
	}
  /* USER CODE END 3 */
}

/**
  * @brief System Clock Configuration
  * @retval None
  */
void SystemClock_Config(void)
{
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Configure the main internal regulator output voltage
  */
  __HAL_RCC_PWR_CLK_ENABLE();
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE1);

  /** Initializes the RCC Oscillators according to the specified parameters
  * in the RCC_OscInitTypeDef structure.
  */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSI|RCC_OSCILLATORTYPE_LSE;
  RCC_OscInitStruct.LSEState = RCC_LSE_ON;
  RCC_OscInitStruct.HSIState = RCC_HSI_ON;
  RCC_OscInitStruct.HSICalibrationValue = RCC_HSICALIBRATION_DEFAULT;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSI;
  RCC_OscInitStruct.PLL.PLLM = 8;
  RCC_OscInitStruct.PLL.PLLN = 180;
  RCC_OscInitStruct.PLL.PLLP = RCC_PLLP_DIV2;
  RCC_OscInitStruct.PLL.PLLQ = 3;
  RCC_OscInitStruct.PLL.PLLR = 2;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK)
  {
    Error_Handler();
  }

  /** Activate the Over-Drive mode
  */
  if (HAL_PWREx_EnableOverDrive() != HAL_OK)
  {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
  */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK|RCC_CLOCKTYPE_SYSCLK
                              |RCC_CLOCKTYPE_PCLK1|RCC_CLOCKTYPE_PCLK2;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_HCLK_DIV4;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_HCLK_DIV2;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_5) != HAL_OK)
  {
    Error_Handler();
  }
  HAL_RCC_MCOConfig(RCC_MCO1, RCC_MCO1SOURCE_LSE, RCC_MCODIV_1);
}

/**
  * @brief ADC1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_ADC1_Init(void)
{

  /* USER CODE BEGIN ADC1_Init 0 */

  /* USER CODE END ADC1_Init 0 */

  ADC_ChannelConfTypeDef sConfig = {0};

  /* USER CODE BEGIN ADC1_Init 1 */

  /* USER CODE END ADC1_Init 1 */

  /** Configure the global features of the ADC (Clock, Resolution, Data Alignment and number of conversion)
  */
  hadc1.Instance = ADC1;
  hadc1.Init.ClockPrescaler = ADC_CLOCK_SYNC_PCLK_DIV4;
  hadc1.Init.Resolution = ADC_RESOLUTION_12B;
  hadc1.Init.ScanConvMode = DISABLE;
  hadc1.Init.ContinuousConvMode = DISABLE;
  hadc1.Init.DiscontinuousConvMode = DISABLE;
  hadc1.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_NONE;
  hadc1.Init.ExternalTrigConv = ADC_SOFTWARE_START;
  hadc1.Init.DataAlign = ADC_DATAALIGN_RIGHT;
  hadc1.Init.NbrOfConversion = 1;
  hadc1.Init.DMAContinuousRequests = DISABLE;
  hadc1.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
  if (HAL_ADC_Init(&hadc1) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure for the selected ADC regular channel its corresponding rank in the sequencer and its sample time.
  */
  sConfig.Channel = ADC_CHANNEL_10;
  sConfig.Rank = 1;
  sConfig.SamplingTime = ADC_SAMPLETIME_3CYCLES;
  if (HAL_ADC_ConfigChannel(&hadc1, &sConfig) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN ADC1_Init 2 */

  /* USER CODE END ADC1_Init 2 */

}

/**
  * @brief ADC2 Initialization Function
  * @param None
  * @retval None
  */
static void MX_ADC2_Init(void)
{

  /* USER CODE BEGIN ADC2_Init 0 */

  /* USER CODE END ADC2_Init 0 */

  ADC_ChannelConfTypeDef sConfig = {0};

  /* USER CODE BEGIN ADC2_Init 1 */

  /* USER CODE END ADC2_Init 1 */

  /** Configure the global features of the ADC (Clock, Resolution, Data Alignment and number of conversion)
  */
  hadc2.Instance = ADC2;
  hadc2.Init.ClockPrescaler = ADC_CLOCK_SYNC_PCLK_DIV4;
  hadc2.Init.Resolution = ADC_RESOLUTION_12B;
  hadc2.Init.ScanConvMode = DISABLE;
  hadc2.Init.ContinuousConvMode = DISABLE;
  hadc2.Init.DiscontinuousConvMode = DISABLE;
  hadc2.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_NONE;
  hadc2.Init.ExternalTrigConv = ADC_SOFTWARE_START;
  hadc2.Init.DataAlign = ADC_DATAALIGN_RIGHT;
  hadc2.Init.NbrOfConversion = 1;
  hadc2.Init.DMAContinuousRequests = DISABLE;
  hadc2.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
  if (HAL_ADC_Init(&hadc2) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure for the selected ADC regular channel its corresponding rank in the sequencer and its sample time.
  */
  sConfig.Channel = ADC_CHANNEL_11;
  sConfig.Rank = 1;
  sConfig.SamplingTime = ADC_SAMPLETIME_3CYCLES;
  if (HAL_ADC_ConfigChannel(&hadc2, &sConfig) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN ADC2_Init 2 */

  /* USER CODE END ADC2_Init 2 */

}

/**
  * @brief ADC3 Initialization Function
  * @param None
  * @retval None
  */
static void MX_ADC3_Init(void)
{

  /* USER CODE BEGIN ADC3_Init 0 */

  /* USER CODE END ADC3_Init 0 */

  ADC_ChannelConfTypeDef sConfig = {0};

  /* USER CODE BEGIN ADC3_Init 1 */

  /* USER CODE END ADC3_Init 1 */

  /** Configure the global features of the ADC (Clock, Resolution, Data Alignment and number of conversion)
  */
  hadc3.Instance = ADC3;
  hadc3.Init.ClockPrescaler = ADC_CLOCK_SYNC_PCLK_DIV4;
  hadc3.Init.Resolution = ADC_RESOLUTION_12B;
  hadc3.Init.ScanConvMode = DISABLE;
  hadc3.Init.ContinuousConvMode = DISABLE;
  hadc3.Init.DiscontinuousConvMode = DISABLE;
  hadc3.Init.ExternalTrigConvEdge = ADC_EXTERNALTRIGCONVEDGE_NONE;
  hadc3.Init.ExternalTrigConv = ADC_SOFTWARE_START;
  hadc3.Init.DataAlign = ADC_DATAALIGN_RIGHT;
  hadc3.Init.NbrOfConversion = 1;
  hadc3.Init.DMAContinuousRequests = DISABLE;
  hadc3.Init.EOCSelection = ADC_EOC_SINGLE_CONV;
  if (HAL_ADC_Init(&hadc3) != HAL_OK)
  {
    Error_Handler();
  }

  /** Configure for the selected ADC regular channel its corresponding rank in the sequencer and its sample time.
  */
  sConfig.Channel = ADC_CHANNEL_12;
  sConfig.Rank = 1;
  sConfig.SamplingTime = ADC_SAMPLETIME_3CYCLES;
  if (HAL_ADC_ConfigChannel(&hadc3, &sConfig) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN ADC3_Init 2 */

  /* USER CODE END ADC3_Init 2 */

}

/**
  * @brief CAN1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_CAN1_Init(void)
{

  /* USER CODE BEGIN CAN1_Init 0 */

  /* USER CODE END CAN1_Init 0 */

  /* USER CODE BEGIN CAN1_Init 1 */

  /* USER CODE END CAN1_Init 1 */
  hcan1.Instance = CAN1;
  hcan1.Init.Prescaler = 16;
  hcan1.Init.Mode = CAN_MODE_NORMAL;
  hcan1.Init.SyncJumpWidth = CAN_SJW_1TQ;
  hcan1.Init.TimeSeg1 = CAN_BS1_1TQ;
  hcan1.Init.TimeSeg2 = CAN_BS2_1TQ;
  hcan1.Init.TimeTriggeredMode = DISABLE;
  hcan1.Init.AutoBusOff = DISABLE;
  hcan1.Init.AutoWakeUp = DISABLE;
  hcan1.Init.AutoRetransmission = DISABLE;
  hcan1.Init.ReceiveFifoLocked = DISABLE;
  hcan1.Init.TransmitFifoPriority = DISABLE;
  if (HAL_CAN_Init(&hcan1) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN CAN1_Init 2 */

  /* USER CODE END CAN1_Init 2 */

}

/**
  * @brief DAC Initialization Function
  * @param None
  * @retval None
  */
static void MX_DAC_Init(void)
{

  /* USER CODE BEGIN DAC_Init 0 */

  /* USER CODE END DAC_Init 0 */

  DAC_ChannelConfTypeDef sConfig = {0};

  /* USER CODE BEGIN DAC_Init 1 */

  /* USER CODE END DAC_Init 1 */

  /** DAC Initialization
  */
  hdac.Instance = DAC;
  if (HAL_DAC_Init(&hdac) != HAL_OK)
  {
    Error_Handler();
  }

  /** DAC channel OUT1 config
  */
  sConfig.DAC_Trigger = DAC_TRIGGER_NONE;
  sConfig.DAC_OutputBuffer = DAC_OUTPUTBUFFER_ENABLE;
  if (HAL_DAC_ConfigChannel(&hdac, &sConfig, DAC_CHANNEL_1) != HAL_OK)
  {
    Error_Handler();
  }

  /** DAC channel OUT2 config
  */
  if (HAL_DAC_ConfigChannel(&hdac, &sConfig, DAC_CHANNEL_2) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN DAC_Init 2 */

  /* USER CODE END DAC_Init 2 */

}

/**
  * @brief SPI1 Initialization Function
  * @param None
  * @retval None
  */
static void MX_SPI1_Init(void)
{

  /* USER CODE BEGIN SPI1_Init 0 */

  /* USER CODE END SPI1_Init 0 */

  /* USER CODE BEGIN SPI1_Init 1 */

  /* USER CODE END SPI1_Init 1 */
  /* SPI1 parameter configuration*/
  hspi1.Instance = SPI1;
  hspi1.Init.Mode = SPI_MODE_MASTER;
  hspi1.Init.Direction = SPI_DIRECTION_2LINES;
  hspi1.Init.DataSize = SPI_DATASIZE_8BIT;
  hspi1.Init.CLKPolarity = SPI_POLARITY_LOW;
  hspi1.Init.CLKPhase = SPI_PHASE_1EDGE;
  hspi1.Init.NSS = SPI_NSS_SOFT;
  hspi1.Init.BaudRatePrescaler = SPI_BAUDRATEPRESCALER_2;
  hspi1.Init.FirstBit = SPI_FIRSTBIT_MSB;
  hspi1.Init.TIMode = SPI_TIMODE_DISABLE;
  hspi1.Init.CRCCalculation = SPI_CRCCALCULATION_DISABLE;
  hspi1.Init.CRCPolynomial = 10;
  if (HAL_SPI_Init(&hspi1) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN SPI1_Init 2 */

  /* USER CODE END SPI1_Init 2 */

}

/**
  * @brief TIM2 Initialization Function
  * @param None
  * @retval None
  */
static void MX_TIM2_Init(void)
{

  /* USER CODE BEGIN TIM2_Init 0 */

  /* USER CODE END TIM2_Init 0 */

  TIM_ClockConfigTypeDef sClockSourceConfig = {0};
  TIM_MasterConfigTypeDef sMasterConfig = {0};
  TIM_IC_InitTypeDef sConfigIC = {0};

  /* USER CODE BEGIN TIM2_Init 1 */

  /* USER CODE END TIM2_Init 1 */
  htim2.Instance = TIM2;
  htim2.Init.Prescaler = 0;
  htim2.Init.CounterMode = TIM_COUNTERMODE_UP;
  htim2.Init.Period = 4294967295;
  htim2.Init.ClockDivision = TIM_CLOCKDIVISION_DIV1;
  htim2.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;
  if (HAL_TIM_Base_Init(&htim2) != HAL_OK)
  {
    Error_Handler();
  }
  sClockSourceConfig.ClockSource = TIM_CLOCKSOURCE_INTERNAL;
  if (HAL_TIM_ConfigClockSource(&htim2, &sClockSourceConfig) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_TIM_IC_Init(&htim2) != HAL_OK)
  {
    Error_Handler();
  }
  sMasterConfig.MasterOutputTrigger = TIM_TRGO_RESET;
  sMasterConfig.MasterSlaveMode = TIM_MASTERSLAVEMODE_DISABLE;
  if (HAL_TIMEx_MasterConfigSynchronization(&htim2, &sMasterConfig) != HAL_OK)
  {
    Error_Handler();
  }
  sConfigIC.ICPolarity = TIM_INPUTCHANNELPOLARITY_RISING;
  sConfigIC.ICSelection = TIM_ICSELECTION_DIRECTTI;
  sConfigIC.ICPrescaler = TIM_ICPSC_DIV1;
  sConfigIC.ICFilter = 0;
  if (HAL_TIM_IC_ConfigChannel(&htim2, &sConfigIC, TIM_CHANNEL_1) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN TIM2_Init 2 */

  /* USER CODE END TIM2_Init 2 */

}

/**
  * @brief TIM5 Initialization Function
  * @param None
  * @retval None
  */
static void MX_TIM5_Init(void)
{

  /* USER CODE BEGIN TIM5_Init 0 */

  /* USER CODE END TIM5_Init 0 */

  TIM_ClockConfigTypeDef sClockSourceConfig = {0};
  TIM_MasterConfigTypeDef sMasterConfig = {0};
  TIM_IC_InitTypeDef sConfigIC = {0};

  /* USER CODE BEGIN TIM5_Init 1 */

  /* USER CODE END TIM5_Init 1 */
  htim5.Instance = TIM5;
  htim5.Init.Prescaler = 0;
  htim5.Init.CounterMode = TIM_COUNTERMODE_UP;
  htim5.Init.Period = 4294967295;
  htim5.Init.ClockDivision = TIM_CLOCKDIVISION_DIV1;
  htim5.Init.AutoReloadPreload = TIM_AUTORELOAD_PRELOAD_DISABLE;
  if (HAL_TIM_Base_Init(&htim5) != HAL_OK)
  {
    Error_Handler();
  }
  sClockSourceConfig.ClockSource = TIM_CLOCKSOURCE_INTERNAL;
  if (HAL_TIM_ConfigClockSource(&htim5, &sClockSourceConfig) != HAL_OK)
  {
    Error_Handler();
  }
  if (HAL_TIM_IC_Init(&htim5) != HAL_OK)
  {
    Error_Handler();
  }
  sMasterConfig.MasterOutputTrigger = TIM_TRGO_RESET;
  sMasterConfig.MasterSlaveMode = TIM_MASTERSLAVEMODE_DISABLE;
  if (HAL_TIMEx_MasterConfigSynchronization(&htim5, &sMasterConfig) != HAL_OK)
  {
    Error_Handler();
  }
  sConfigIC.ICPolarity = TIM_INPUTCHANNELPOLARITY_RISING;
  sConfigIC.ICSelection = TIM_ICSELECTION_DIRECTTI;
  sConfigIC.ICPrescaler = TIM_ICPSC_DIV1;
  sConfigIC.ICFilter = 0;
  if (HAL_TIM_IC_ConfigChannel(&htim5, &sConfigIC, TIM_CHANNEL_2) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN TIM5_Init 2 */

  /* USER CODE END TIM5_Init 2 */

}

/**
  * @brief USART2 Initialization Function
  * @param None
  * @retval None
  */
static void MX_USART2_UART_Init(void)
{

  /* USER CODE BEGIN USART2_Init 0 */

  /* USER CODE END USART2_Init 0 */

  /* USER CODE BEGIN USART2_Init 1 */

  /* USER CODE END USART2_Init 1 */
  huart2.Instance = USART2;
  huart2.Init.BaudRate = 115200;
  huart2.Init.WordLength = UART_WORDLENGTH_8B;
  huart2.Init.StopBits = UART_STOPBITS_1;
  huart2.Init.Parity = UART_PARITY_NONE;
  huart2.Init.Mode = UART_MODE_TX_RX;
  huart2.Init.HwFlowCtl = UART_HWCONTROL_NONE;
  huart2.Init.OverSampling = UART_OVERSAMPLING_16;
  if (HAL_UART_Init(&huart2) != HAL_OK)
  {
    Error_Handler();
  }
  /* USER CODE BEGIN USART2_Init 2 */

  /* USER CODE END USART2_Init 2 */

}

/**
  * @brief GPIO Initialization Function
  * @param None
  * @retval None
  */
static void MX_GPIO_Init(void)
{
  GPIO_InitTypeDef GPIO_InitStruct = {0};
/* USER CODE BEGIN MX_GPIO_Init_1 */
/* USER CODE END MX_GPIO_Init_1 */

  /* GPIO Ports Clock Enable */
  __HAL_RCC_GPIOC_CLK_ENABLE();
  __HAL_RCC_GPIOA_CLK_ENABLE();
  __HAL_RCC_GPIOB_CLK_ENABLE();

  /*Configure GPIO pin Output Level */
  HAL_GPIO_WritePin(GPIOC, GPIO_PIN_7, GPIO_PIN_RESET);

  /*Configure GPIO pin : PA6 */
  GPIO_InitStruct.Pin = GPIO_PIN_6;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

  /*Configure GPIO pin : PC7 */
  GPIO_InitStruct.Pin = GPIO_PIN_7;
  GPIO_InitStruct.Mode = GPIO_MODE_OUTPUT_OD;
  GPIO_InitStruct.Pull = GPIO_PULLUP;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  HAL_GPIO_Init(GPIOC, &GPIO_InitStruct);

  /*Configure GPIO pin : PC8 */
  GPIO_InitStruct.Pin = GPIO_PIN_8;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(GPIOC, &GPIO_InitStruct);

  /*Configure GPIO pin : PA8 */
  GPIO_InitStruct.Pin = GPIO_PIN_8;
  GPIO_InitStruct.Mode = GPIO_MODE_AF_PP;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  GPIO_InitStruct.Speed = GPIO_SPEED_FREQ_LOW;
  GPIO_InitStruct.Alternate = GPIO_AF0_MCO;
  HAL_GPIO_Init(GPIOA, &GPIO_InitStruct);

  /*Configure GPIO pin : PB6 */
  GPIO_InitStruct.Pin = GPIO_PIN_6;
  GPIO_InitStruct.Mode = GPIO_MODE_INPUT;
  GPIO_InitStruct.Pull = GPIO_NOPULL;
  HAL_GPIO_Init(GPIOB, &GPIO_InitStruct);

/* USER CODE BEGIN MX_GPIO_Init_2 */
/* USER CODE END MX_GPIO_Init_2 */
}

/* USER CODE BEGIN 4 */
//Only have access to GPIO pins in main
void csv_header(char *file_name, int file_length) {
	char name[file_length];
	strcpy(name, file_name);
	if (HAL_GPIO_ReadPin(GPIOB, GPIO_PIN_6)) {
		file_res = sd_mount("/");

		//Write to CSV using the following format for each column:
		//sprintf(buffer, "<Column Title>,");
		//update_file(name, buffer);

		file_res = file_update(name, buffer);
		sd_unmount("/");

	}
}

void csv_update(char *file_name, int file_length) {

	char name[file_length];
	strcpy(name, file_name);

	if (HAL_GPIO_ReadPin(GPIOB, GPIO_PIN_6)) {
		file_res = sd_mount("/");
		//Update CSV using following format:
		//sprintf(buffer, "<%unit>, measurement name"
		//update_file(name, buffer);

		sprintf(buffer, "\n\n");
		file_res = file_update(name, buffer);
		sd_unmount("/");
	}

}

void HAL_TIM_IC_CaptureCallback(TIM_HandleTypeDef *htim) {
	if (htim->Channel == HAL_TIM_ACTIVE_CHANNEL_1) {
		if (tim2.Is_First_Captured == 0) {
			tim2.IC_Value1 = HAL_TIM_ReadCapturedValue(htim, TIM_CHANNEL_1);
			tim2.Is_First_Captured = 1;
		} else if (tim2.Is_First_Captured) {
			tim2.IC_Value2 = HAL_TIM_ReadCapturedValue(htim, TIM_CHANNEL_1);
			if (tim2.IC_Value2 > tim2.IC_Value1) {
				tim2.Current_Frequency = tim2.Frequency;
				tim2.Difference = tim2.IC_Value2 - tim2.IC_Value1;
				tim2.Frequency = HAL_RCC_GetPCLK1Freq() / tim2.Difference;
				tim2.CalculationOK = 1;
				if (check_outliers(tim2.Current_Frequency, tim2.Frequency)) {
					if (tim2.outlier_counter >= OUTLIER_COUNT) {
						tim2.outlier_counter = 0;
						return;
					}
					if (tim2.outlier_counter == 0) {
						tim2.Good_Frequency = tim2.Current_Frequency;
					}
					++tim2.outlier_counter;
				} else {
					if (tim2.outlier_counter != 0)
						tim2.outlier_counter = 0;
				}
			} else {
				tim2.CalculationOK = 0;
			}
			tim2.Is_First_Captured = 0;
		}
	}
	if (htim->Channel == HAL_TIM_ACTIVE_CHANNEL_2) {
		if (tim5.Is_First_Captured == 0) {
			tim5.IC_Value1 = HAL_TIM_ReadCapturedValue(htim, TIM_CHANNEL_2);
			tim5.Is_First_Captured = 1;
		}
		else if (tim5.Is_First_Captured) {
			tim5.IC_Value2 = HAL_TIM_ReadCapturedValue(htim, TIM_CHANNEL_2);
			if (tim5.IC_Value2 > tim5.IC_Value1) {
				tim5.Current_Frequency = tim5.Frequency;
				tim5.Difference = tim5.IC_Value2 - tim5.IC_Value1;
				tim5.Frequency = HAL_RCC_GetPCLK1Freq() / tim5.Difference;
				tim5.CalculationOK = 1;
				if (check_outliers(tim5.Current_Frequency, tim5.Frequency)) {
					if (tim5.outlier_counter >= OUTLIER_COUNT) {
						tim5.outlier_counter = 0;
						return;
					}
					if (tim5.outlier_counter == 0) {
						tim5.Good_Frequency = tim5.Current_Frequency;
					}
					++tim5.outlier_counter;
				} else {
					if (tim5.outlier_counter != 0)
						tim5.outlier_counter = 0;
				}
			} else {
				tim5.CalculationOK = 0;
			}
			tim5.Is_First_Captured = 0;
		}

	}
}

void HAL_ADC_ConvCpltCallback(ADC_HandleTypeDef *hadc) {
	float f;
	uint16_t val;

	val = HAL_ADC_GetValue(hadc);
	if (hadc == &hadc1) { // Throttle Input 1
		push_adc_buf(&adc_buf1, val);
		f = convert_throttle_input(val);
		push_throttle_in_buf(&throttle_buf, f);
	} else if (hadc == &hadc2) { // Throttle Input 2
		push_adc_buf(&adc_buf2, val);
	} else if (hadc == &hadc3) { // Steering angle sensor, extra analog input
		push_adc_buf(&adc_buf3, val);
		f = convert_steering_wheel_angle(val);
		f = steering_wheel_angle_to_steering_angle(f);
		push_steering_angle_buf(&steering_angle_buf, f);
	}
}

void HAL_CAN_RxFifo0MsgPendingCallback(CAN_HandleTypeDef *hcan) {
	HAL_CAN_GetRxMessage(hcan, CAN_RX_FIFO0, &rxHeader, canRX);
	// HAL_GPIO_TogglePin(LD2_GPIO_Port, LD2_Pin);

	if (rxHeader.StdId == 0x0A7) {
		/*for (loop = 0; loop < 8; loop++)

			printf("%d ", canRX[loop]);
		printf("Receiving data from TxHeader: %u\r\n", rxHeader);*/
		voltage = ((canRX[1] * 256 + canRX[0]) / 10);
		//printf("Voltage %d\r\n", voltage);

	}
	if (rxHeader.StdId == 0x0A5) {
		/*for (loop = 0; loop < 8; loop++)

			printf("%d ", canRX[loop]);
		printf("Receiving data from TxHeader: %u\r\n", rxHeader);*/
		RPM = (canRX[3] * 256 + canRX[2]);
		//printf("RPM: %d\r\n", RPM);

	}
	if (rxHeader.StdId == 0x0A6) {
		/*for (loop = 0; loop < 8; loop++)

			printf("%d ", canRX[loop]);
		printf("Receiving data from TxHeader: %u\r\n", rxHeader);*/
		current = ((canRX[7] * 256 + canRX[6]) / 10);
		//printf("Current %d\r\n", current);

	}
	power = current * voltage;
	//printf("Power %d\r\n", power);

}

int __io_putchar(int ch) {
	uint8_t c[1];
	c[0] = ch & 0x00FF;
	HAL_UART_Transmit_IT(&huart2, &*c, sizeof(c));
	return ch;
}
/* USER CODE END 4 */

/**
  * @brief  This function is executed in case of error occurrence.
  * @retval None
  */
void Error_Handler(void)
{
  /* USER CODE BEGIN Error_Handler_Debug */
	/* User can add his own implementation to report the HAL error return state */
	__disable_irq();
	while (1) {
	}
  /* USER CODE END Error_Handler_Debug */
}

#ifdef  USE_FULL_ASSERT
/**
  * @brief  Reports the name of the source file and the source line number
  *         where the assert_param error has occurred.
  * @param  file: pointer to the source file name
  * @param  line: assert_param error line source number
  * @retval None
  */
void assert_failed(uint8_t *file, uint32_t line)
{
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line number,
     ex: printf("Wrong parameters value: file %s on line %d\r\n", file, line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */

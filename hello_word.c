/******************************************************************************
* Copyright (C) 2023 Advanced Micro Devices, Inc. All Rights Reserved.
* SPDX-License-Identifier: MIT
******************************************************************************/
/*
 * helloworld.c: simple test application
 *
 * This application configures UART 16550 to baud rate 9600.
 * PS7 UART (Zynq) is not initialized by this application, since
 * bootrom/bsp configures it to baud rate 115200
 *
 * ------------------------------------------------
 * | UART TYPE   BAUD RATE                        |
 * ------------------------------------------------
 *   uartns550   9600
 *   uartlite    Configurable only in HW design
 *   ps7_uart    115200 (configured by bootrom/bsp)
 */

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include "platform.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xgpio.h"

int main()
{
    // Initialize platform
    init_platform();

    // Print welcome message
    xil_printf("Welcome to ECE 327/627 HW Wordle!\r\n");

    // Declare all PL GPIOs
    XGpio game_status, guess_count, guess_word, ready, ref_word_id, result, guess_id;

    // Initialize and set direction of PL input GPIOs
    XGpio_Initialize(&ref_word_id, XPAR_REF_WORD_IDX_BASEADDR);
    XGpio_SetDataDirection(&ref_word_id, 1, 0x00);
    XGpio_Initialize(&guess_word, XPAR_GUESS_WORD_BASEADDR);
    XGpio_SetDataDirection(&guess_word, 1, 0x00);
    XGpio_Initialize(&guess_id, XPAR_GUESS_ID_BASEADDR);
    XGpio_SetDataDirection(&guess_id, 1, 0x00);

    // Initialize and set direction of PL output GPIOs
    XGpio_Initialize(&ready, XPAR_READY_BASEADDR);
    XGpio_SetDataDirection(&ready, 1, 0x01);
    XGpio_Initialize(&result, XPAR_RESULT_BASEADDR);
    XGpio_SetDataDirection(&result, 1, 0x01);
    XGpio_Initialize(&guess_count, XPAR_GUESS_COUNT_BASEADDR);
    XGpio_SetDataDirection(&guess_count, 1, 0x01);
    XGpio_Initialize(&game_status, XPAR_GAME_STATUS_BASEADDR);
    XGpio_SetDataDirection(&game_status, 1, 0x01);

    // Declare variables
    char user_guess[4];
    int user_guess_int;
    int ready_value = 0;
    int game_status_value = 0;
    int guess_count_value = 0;
    int guess_id_value = 0;
    int result_value = 0;
    int ref_word_id_value = 0;

    while (1) {
        // Pick a random word out of the 1024 words stored in PL ROM for the current game
        ref_word_id_value = rand() % 1024;
        XGpio_DiscreteWrite(&ref_word_id, 1, ref_word_id_value);
        xil_printf("Puzzle ID: %d \r\n", ref_word_id_value);

        // While the current game is not over
        game_status_value = XGpio_DiscreteRead(&game_status, 1);
        while (!game_status_value) {
            // Wait for wordle FSM to be ready to accept a new input
            while(!ready_value) ready_value = XGpio_DiscreteRead(&ready, 1);
            ready_value = 0;

            // Accept user guess word, convert it to 32-bit value, and write it to Wordle FSM
            xil_printf("Enter guess: ");
            scanf("%s", &user_guess);
            user_guess_int = 0;
            for (int i = 0; i < 4; i++) {
                user_guess[i] = tolower(user_guess[i]);
                user_guess_int |= (user_guess[i] << (3-i)*8);
            }
            XGpio_DiscreteWrite(&guess_word, 1, user_guess_int);
            XGpio_DiscreteWrite(&guess_id, 1, ++guess_id_value);

            // If game is not over, wait until Wordle FSM is ready to accept new input
            ready_value = XGpio_DiscreteRead(&ready, 1);
            game_status_value = XGpio_DiscreteRead(&game_status, 1);
            while (!ready_value && game_status_value) {
                ready_value = XGpio_DiscreteRead(&ready, 1);
                game_status_value = XGpio_DiscreteRead(&game_status, 1);
                if (game_status_value != 0) break;
            }

            // Read and display round result
            guess_count_value = XGpio_DiscreteRead(&guess_count, 1);
            result_value = XGpio_DiscreteRead(&result, 1);
            xil_printf("Round %d result: ", guess_count_value, result_value);
            for(int i = 0; i < 4; i++) {
                int temp = (result_value >> (2*(3-i))) & 0x00000003;
                if (temp == 0) xil_printf("X");
                else if (temp == 1) xil_printf("G");
                else xil_printf("Y");
            }
            xil_printf("\r\n");

            // If game is over, display final message
            if (game_status_value == 2) { 
                xil_printf("You LOST! It's okay ... you can try again!\r\n");
                xil_printf("==================================================\r\n");
                guess_id_value = 0;
                XGpio_DiscreteWrite(&guess_id, 1, guess_id_value);
            } else if (game_status_value == 3) { 
                xil_printf("You WON! Probably this word was too easy :P\r\n");
                xil_printf("==================================================\r\n");
                guess_id_value = 0;
                XGpio_DiscreteWrite(&guess_id, 1, guess_id_value);
            }
            
        }
    }

    cleanup_platform();
    return 0;
}

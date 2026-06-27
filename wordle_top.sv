/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 2                                           */
/* Wordle Top-Level Module                         */
/***************************************************/

// This module instantiates the word ROM and your Wordle FSM as sub-components.
// The word produced by the ROM is provided to the FSM as the reference word.

module wordle_top #(
    parameter NUM_LETTERS = 4,                      // Word size in letters
    parameter WORD_WIDTH = NUM_LETTERS * 8,         // Word bitwidth
    parameter RSLT_WIDTH = NUM_LETTERS * 2,         // Result bitwidth
    parameter MAX_GUESSES = 6,                      // Maximum number of allowed guesses
    parameter GUESS_CNTW = $clog2(MAX_GUESSES) + 1, // Bitwidth of guess counter
    parameter DICT_SIZE = 1024,                     // Depth of the word ROM
    parameter ADDR_WIDTH = $clog2(DICT_SIZE)        // Bitwidth of ROM address
 )(
    input clk,                              // Input clock
    input rstn,                             // Input active-low reset
    input [ADDR_WIDTH-1:0] i_ref_word_idx,  // Index of the ROM word to be used for the game
    input [WORD_WIDTH-1:0] i_guess_word,    // Input user guess word
    input [GUESS_CNTW-1:0] i_guess_id,      // Input user guess ID
    output o_ready,                         // Output ready signal (result is valid & ready to accept new guess word)
    output [RSLT_WIDTH-1:0] o_result,       // Output result of a guess (4 letters x 2-bit status: GREEN, YELLOW, GREY)
    output [GUESS_CNTW-1:0] o_guess_count,  // Output number of user guesses so far
    output [1:0] o_game_status              // Output game status (ongoing, user won, user lost)
);

logic [WORD_WIDTH-1:0] ref_word;    // Reference word signal to connect ROM module to FSM module

// Instantiate Wordle FSM module
wordle_fsm # (
    .NUM_LETTERS(NUM_LETTERS),
    .MAX_GUESSES(MAX_GUESSES)
) fsm_inst (
    .clk(clk), 
    .rstn(rstn),
    .i_ref_word(ref_word),
    .i_guess_word(i_guess_word),
    .i_guess_id(i_guess_id),
    .o_ready(o_ready),
    .o_result(o_result),
    .o_guess_count(o_guess_count),
    .o_game_status(o_game_status)
);

// Instantiate Wordle ROM module
wordle_rom # (
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(WORD_WIDTH)
) rom_inst (
    .clk(clk),
    .addr(i_ref_word_idx),
    .data(ref_word)
);

endmodule
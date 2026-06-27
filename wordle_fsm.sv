/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 2                                           */
/* Wordle FSM Module                               */
/***************************************************/

module wordle_fsm #(
    parameter NUM_LETTERS = 4,                      // Word size in letters
    parameter WORD_WIDTH = NUM_LETTERS * 8,         // Word bitwidth
    parameter RSLT_WIDTH = NUM_LETTERS * 2,         // Result bitwidth
    parameter MAX_GUESSES = 6,                      // Maximum number of allowed guesses
    parameter GUESS_CNTW = $clog2(MAX_GUESSES) + 1  // Bitwidth of guess counter
)(
    input clk,                              // Input clock
    input rstn,                             // Input active-low reset
    input [WORD_WIDTH-1:0] i_ref_word,      // Input reference word
    input [WORD_WIDTH-1:0] i_guess_word,    // Input user guess word
    input [GUESS_CNTW-1:0] i_guess_id,      // Input user guess ID
    output o_ready,                         // Output ready signal (result is valid & ready to accept new guess word)
    output [RSLT_WIDTH-1:0] o_result,       // Output result of a guess (4 letters x 2-bit status: GREEN, YELLOW, GREY)
    output [GUESS_CNTW-1:0] o_guess_count,  // Output number of user guesses so far
    output [1:0] o_game_status              // Output game status (ongoing, user won, user lost)
);

// Declare registers to hold game result, guess count, and status
enum logic [1:0] {GREY = 2'b00, GREEN = 2'b01, YELLOW = 2'b10} r_result [0:NUM_LETTERS-1], computed_result [0:NUM_LETTERS-1];
logic [GUESS_CNTW-1:0] r_guess_count;
enum logic [1:0] {ONGOING = 2'b00, WIN = 2'b11, LOSE = 2'b10} r_game_status, game_status;

/******* Your code starts here *******/

enum {RST, WAITING, PROCESS, LATCH, DONE} state, next_state;
logic [GUESS_CNTW-1:0] r_guess_id;
logic ready_wire;
logic all_green;
logic [WORD_WIDTH-1:0] r_ref_word;
logic [WORD_WIDTH-1:0] r_guess_word;

always_ff @(posedge clk) begin
    if (!rstn) begin
        state         <= RST;
        r_result      <= '{default: GREY};
        r_game_status <= ONGOING;
        r_guess_count <= '0;
        r_guess_id    <= '0;
        r_ref_word    <= '0;
        r_guess_word  <= '0;
    end else begin
        state <= next_state;

        // Latch the new guess (word + id) when it arrives in WAITING.
        // Capture the reference word at the same time: the ROM is synchronous
        // (1-cycle latency), so by the time a guess is accepted in WAITING the
        // ROM output (i_ref_word) has long been stable. i_ref_word_idx is held
        // for the whole game, so this also re-captures the correct word for a
        // new game (r_guess_id resets to 0, so the first new guess re-latches).
        if (state == WAITING && i_guess_id > r_guess_id) begin
            r_guess_word <= i_guess_word;
            r_guess_id   <= i_guess_id;
            r_ref_word   <= i_ref_word;
        end

        // Commit result, count, and status together in the LATCH cycle, AFTER
        // PROCESS has computed them. PROCESS computes combinationally from the
        // guess that was registered the cycle we left WAITING; LATCH registers
        // the outputs. This guarantees the guess data is stable before it is
        // consumed (no same-edge race between latching the guess and reading it).
        if (state == LATCH) begin
            r_result      <= computed_result;
            r_guess_count <= r_guess_count + 1'b1;
            r_game_status <= game_status;
        end

        // Clean restart: from DONE (win/lose) when the harness drops i_guess_id to 0.
        if (state == DONE && i_guess_id == 0) begin
            r_guess_count <= '0;
            r_guess_id    <= '0;
            r_result      <= '{default: GREY};
            r_game_status <= ONGOING;
        end
    end
end

always_comb begin: state_decoder
    //   Defaults (prevent latches; every driven signal gets a default)  
    next_state  = state;
    ready_wire  = 1'b0;
    game_status = r_game_status;
    all_green   = 1'b1;
    for (int i = 0; i < NUM_LETTERS; i++)
        computed_result[i] = GREY;

    case (state)
        RST: next_state = WAITING;

        WAITING: begin
            ready_wire = 1'b1;               // ready & result valid while waiting for a guess
            if (i_guess_id > r_guess_id)
                next_state = PROCESS;
            else
                next_state = WAITING;
        end

        PROCESS, LATCH: begin
            ready_wire = 1'b0;
            // Compute the result combinationally in BOTH PROCESS and LATCH.
            // It is registered on the LATCH edge (see always_ff), at which point
            // r_guess_word/r_ref_word have been stable for a full cycle, so there
            // is no same-edge race between latching the guess and reading it.
            begin
                logic [7:0] ref_letters   [0:NUM_LETTERS-1];
                logic [7:0] guess_letters [0:NUM_LETTERS-1];
                logic [1:0] arr           [0:NUM_LETTERS-1];   // 0=grey, 1=green, 2=yellow

                //   Unpack words into byte arrays (letter 0 = MSB)  
                for (int i = 0; i < NUM_LETTERS; i++) begin
                    ref_letters[i]   = r_ref_word  [(NUM_LETTERS-1-i)*8 +: 8];
                    guess_letters[i] = r_guess_word[(NUM_LETTERS-1-i)*8 +: 8];
                    arr[i] = 2'd0;   // default grey
                end

                //   Phase 1: GREEN pass  
                for (int i = 0; i < NUM_LETTERS; i++) begin
                    if (guess_letters[i] == ref_letters[i]) begin
                        arr[i] = 2'd1;            // green
                        ref_letters[i] = 8'hFF;   // consume so it can't be reused
                    end
                end

                //   Phase 2: YELLOW pass (right-to-left so last occurrence wins)  
                for (int i = NUM_LETTERS-1; i >= 0; i--) begin
                    if (arr[i] == 2'd0) begin
                        for (int k = 0; k < NUM_LETTERS; k++) begin
                            if (guess_letters[i] == ref_letters[k]) begin
                                arr[i] = 2'd2;
                                ref_letters[k] = 8'hFF;
                                break;
                            end
                        end
                    end
                end

                //   Phase 3: build computed_result (letter 0 -> MSB slot, matching SW)  
                for (int i = 0; i < NUM_LETTERS; i++) begin
                    case (arr[i])
                        2'd0:    computed_result[NUM_LETTERS-1-i] = GREY;
                        2'd1:    computed_result[NUM_LETTERS-1-i] = GREEN;
                        2'd2:    computed_result[NUM_LETTERS-1-i] = YELLOW;
                        default: computed_result[NUM_LETTERS-1-i] = GREY;
                    endcase
                end
            end

            //   Win / lose decision (consumed only on the LATCH edge)  
            all_green = 1'b1;
            for (int i = 0; i < NUM_LETTERS; i++) begin
                if (computed_result[i] != GREEN)
                    all_green = 1'b0;
            end

            if (state == PROCESS) begin
                next_state = LATCH;          // one settle cycle, then register
            end else begin                   // state == LATCH: decide outcome
                if (all_green) begin
                    game_status = WIN;
                    next_state  = DONE;
                end else if (r_guess_count + 1'b1 == GUESS_CNTW'(MAX_GUESSES)) begin
                    game_status = LOSE;
                    next_state  = DONE;
                end else begin
                    game_status = ONGOING;
                    next_state  = WAITING;
                end
            end
        end

        DONE: begin
            ready_wire = 1'b0;               // ready stays de-asserted on win/lose
            if (i_guess_id == 0)
                next_state = RST;            // restart a new game
            else
                next_state = DONE;
        end

        default: next_state = RST;
    endcase
end

assign o_ready = ready_wire;   // combinational: no one-cycle lag
/******* Your code ends here ********/

// Connect game result, guess count, and status output ports to the declared corresponding registers
genvar j;
generate
    for (j = 0; j < NUM_LETTERS; j = j + 1) begin: assign_result
        // The indexing syntax used below [M+:N] extracts an N-bit slice of a bitvector starting from bit M (i.e., equivalent to [M+N-1:M])
        assign o_result[j*2+:2] = r_result[j];
    end
endgenerate
assign o_guess_count = r_guess_count;
assign o_game_status = r_game_status;

endmodule
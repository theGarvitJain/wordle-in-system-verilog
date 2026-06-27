/***************************************************/
/* ECE 327: Digital Hardware Systems - Spring 2026 */
/* Lab 2                                           */
/* Wordle Game Testbench                           */
/***************************************************/
`timescale 1ns / 1ps
// Define the name of this testbench module. Since testbenches typically generate inputs and
// monitor outputs of the circuit being tested, they usually do not have any input/output ports.
module wordle_top_tb();
localparam CLK_PERIOD = 2;                          // Clock period in nanoseconds
localparam NUM_LETTERS = 4;                         // Word size in letters
localparam WORD_WIDTH = NUM_LETTERS * 8;            // Word bitwidth
localparam RSLT_WIDTH = NUM_LETTERS * 2;            // Result bitwidth
localparam MAX_GUESSES = 6;                         // Maximum number of allowed guesses
localparam GUESS_CNTW = $clog2(MAX_GUESSES) + 1;    // Bitwidth of guess counter
localparam DICT_SIZE = 1024;                        // Depth of the word ROM
localparam ADDR_WIDTH = $clog2(DICT_SIZE);          // Bitwidth of ROM address
// Declare logic signals for the circuit's inputs/outputs
logic clk;
logic rstn;
logic [ADDR_WIDTH-1:0] i_ref_word_idx;
logic [WORD_WIDTH-1:0] i_guess_word;
logic [GUESS_CNTW-1:0] i_guess_id;
logic o_ready;
logic [RSLT_WIDTH-1:0] o_result;
logic [GUESS_CNTW-1:0] o_guess_count;
logic [1:0] o_game_status;
// Signal to identify if simulation passed (1'b0) or failed (1'b1). Your testbench should test
// the design and set this signal accordingly.
logic sim_failed;
// Instantiate the design under test (dut), set the desired values of its parameters, and connect
// its input/output ports to the declared signals.
wordle_top dut (
    .clk(clk),
    .rstn(rstn),
    .i_ref_word_idx(i_ref_word_idx),
    .i_guess_word(i_guess_word),
    .i_guess_id(i_guess_id),
    .o_ready(o_ready),
    .o_result(o_result),
    .o_guess_count(o_guess_count),
    .o_game_status(o_game_status)
);
// This initial block generates a clock signal
initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end
/******* Your code starts here *******/

// ---------------------------------------------------------------------------
// Status / color encodings (must match the FSM enums and the lab spec).
// ---------------------------------------------------------------------------
localparam logic [1:0] GREY    = 2'b00, GREEN = 2'b01, YELLOW = 2'b10;
localparam logic [1:0] ONGOING = 2'b00, WIN   = 2'b11, LOSE   = 2'b10;

// ---------------------------------------------------------------------------
// RESULT BIT-ORDER CONVENTION (matches the provided helloworld.c interface):
//   o_result[7:6] = color of letter 0 (the FIRST/leftmost letter)
//   o_result[5:4] = letter 1
//   o_result[3:2] = letter 2
//   o_result[1:0] = letter 3 (the LAST letter)
// i.e. reading an 8'bAABBCCDD constant left-to-right reads the word
// left-to-right, exactly like the string PuTTY prints. This mirrors the word
// packing itself, where letter 0 is the MSB byte ("skim" = 0x736b696d).
// All golden constants below are encoded in this convention. A DUT that packs
// the result in the opposite (LSB-first) order will FAIL these checks.
// ---------------------------------------------------------------------------

// Bookkeeping counters used by the pass/fail reporting.
integer test_id;
integer correct_results;
integer total_checks;
logic [RSLT_WIDTH-1:0] golden_result;   // (declared by skeleton; kept for reference use)

// A bound on how many cycles we ever wait on a handshake edge. If a broken
// DUT never asserts o_ready, we give up, flag a failure, and keep going so
// the simulation always terminates well under the 60 s limit (never hangs).
localparam integer WAIT_GUARD = 100;

// ---------------------------------------------------------------------------
// word2str / rslt2str: human-readable logging helpers only (not used for
// checking). Letter 0 is the MOST-significant byte, matching the FSM's
// unpacking of i_ref_word / i_guess_word (e.g. "skim" = 0x736b696d).
// ---------------------------------------------------------------------------
function automatic string word2str(input logic [WORD_WIDTH-1:0] w);
    string s;
    logic [7:0] c;
    begin
        s = "";
        for (int i = 0; i < NUM_LETTERS; i++) begin
            c = w[(NUM_LETTERS-1-i)*8 +: 8];
            s = {s, string'(c)};
        end
        return s;
    end
endfunction

// Prints letter 0 first. Letter 0's color lives in the MSB pair (j = 3),
// so iterate from the top slice down -- identical to how helloworld.c
// prints the result over UART.
function automatic string rslt2str(input logic [RSLT_WIDTH-1:0] r);
    string s;
    begin
        s = "";
        for (int j = NUM_LETTERS-1; j >= 0; j--) begin
            case (r[j*2 +: 2])
                GREEN:   s = {s, "G"};
                YELLOW:  s = {s, "Y"};
                default: s = {s, "."};
            endcase
        end
        return s;
    end
endfunction

// ---------------------------------------------------------------------------
// Pack a 4-char string into a WORD_WIDTH bus so guesses can be written as
// readable string literals. Letter 0 -> most-significant byte (matches FSM).
// This packs ONLY the testbench-side guess stimulus; the reference word still
// reaches the DUT exclusively through the ROM via i_ref_word_idx.
// ---------------------------------------------------------------------------
function automatic logic [WORD_WIDTH-1:0] str2word(input string s);
    logic [WORD_WIDTH-1:0] w;
    begin
        w = '0;
        for (int i = 0; i < NUM_LETTERS; i++)
            w[(NUM_LETTERS-1-i)*8 +: 8] = s[i];
        return w;
    end
endfunction

// ---------------------------------------------------------------------------
// start_game(idx): begin a fresh game on ROM index `idx`.
//   - Asserts active-low reset, applies the ROM address.
//   - Holds reset long enough for the CLOCKED ROM to latch its word (the ROM
//     registers its output, so ref_word appears one cycle after addr is set).
//   - Releases reset and waits until the FSM presents o_ready (bounded).
// i_guess_id is returned to 0, which is also the WIN/LOSE -> new-game trigger.
// ---------------------------------------------------------------------------
task automatic start_game(input logic [ADDR_WIDTH-1:0] idx);
    integer guard;
    begin
        @(negedge clk);            // drive on falling edge -- no race with the FSM
        rstn           = 1'b0;
        i_guess_id     = '0;
        i_guess_word   = '0;
        i_ref_word_idx = idx;
        @(negedge clk);
        @(negedge clk);            // hold reset; clocked ROM latches the word
        rstn = 1'b1;
        @(negedge clk);            // RST -> WAITING
        guard = 0;
        while (o_ready !== 1'b1 && guard < WAIT_GUARD) begin
            @(negedge clk);
            guard = guard + 1;
        end
    end
endtask

// ---------------------------------------------------------------------------
// do_guess: drive one guess through the o_ready handshake and check the
// DUT result/status against HARDCODED golden values computed by hand from
// the ROM contents (see the case list in the main block). The golden values
// are constants here -- they are NOT produced by any model the DUT shares --
// so a buggy DUT cannot mask its own error.
//
//   exp_result : expected packed o_result (letter 0 in bits [7:6], see note)
//   exp_status : expected o_game_status
//   chk_status : 1 -> also check status; 0 -> skip status check
// ---------------------------------------------------------------------------
task automatic do_guess(
    input logic [WORD_WIDTH-1:0] guess_w,
    input logic [RSLT_WIDTH-1:0] exp_result,
    input logic [1:0]            exp_status,
    input logic                  chk_status
);
    integer guard;
    begin
        // Wait (sampling on negedges) until the DUT is ready
        guard = 0;
        while (o_ready !== 1'b1 && guard < WAIT_GUARD) begin
            @(negedge clk);
            guard = guard + 1;
        end

        // Drive the guess on the falling edge; FSM captures it at the next posedge
        i_guess_word = guess_w;
        i_guess_id   = i_guess_id + 1'b1;

        @(negedge clk);   // by this negedge the FSM has left WAITING (ready=0)
        guard = 0;
        while (o_ready !== 1'b1 && o_game_status == ONGOING
               && guard < WAIT_GUARD) begin
            @(negedge clk);
            guard = guard + 1;
        end

        total_checks = total_checks + 1;
        if (o_result === exp_result) begin
            correct_results = correct_results + 1;
            $display("[%0t] OK   guess=%s got=%s exp=%s status=%b",
                     $time, word2str(guess_w), rslt2str(o_result),
                     rslt2str(exp_result), o_game_status);
        end else begin
            sim_failed = 1'b1;
            $display("[%0t] FAIL guess=%s got=%s exp=%s  <-- RESULT MISMATCH",
                     $time, word2str(guess_w), rslt2str(o_result),
                     rslt2str(exp_result));
        end

        // ---- Optionally check the game status ----
        if (chk_status) begin
            total_checks = total_checks + 1;
            if (o_game_status === exp_status) begin
                correct_results = correct_results + 1;
            end else begin
                sim_failed = 1'b1;
                $display("[%0t] FAIL guess=%s status got=%b exp=%b  <-- STATUS MISMATCH",
                         $time, word2str(guess_w), o_game_status, exp_status);
            end
        end
    end
endtask

// ---------------------------------------------------------------------------
// check_count: verify o_guess_count equals the expected value (counts from 1;
// "won/processed on the Nth guess" -> N)
// ---------------------------------------------------------------------------
task automatic check_count(input logic [GUESS_CNTW-1:0] exp_count);
    begin
        total_checks = total_checks + 1;
        if (o_guess_count === exp_count) begin
            correct_results = correct_results + 1;
        end else begin
            sim_failed = 1'b1;
            $display("[%0t] FAIL guess_count got=%0d exp=%0d  <-- COUNT MISMATCH",
                     $time, o_guess_count, exp_count);
        end
    end
endtask

// ---------------------------------------------------------------------------
// check_not_ready: after a WIN/LOSE the spec requires o_ready to stay low
// ---------------------------------------------------------------------------
task automatic check_not_ready();
    begin
        total_checks = total_checks + 1;
        if (o_ready === 1'b0) begin
            correct_results = correct_results + 1;
        end else begin
            sim_failed = 1'b1;
            $display("[%0t] FAIL o_ready=%b after game end  <-- READY-SHOULD-BE-LOW",
                     $time, o_ready);
        end
    end
endtask

/******* Your code ends here ********/
initial begin
    // Reset all testbench signals
    sim_failed = 1'b0;
    rstn = 1'b0;
    i_ref_word_idx = 'd0;
    i_guess_word = 'd0;
    i_guess_id = 'd0;
    #(5*CLK_PERIOD);
    /******* Your code starts here *******/

    $timeformat(-9, 2, " ns", 0);
    correct_results = 0;
    total_checks    = 0;
    test_id         = 0;

    // =====================================================================
    // Every golden value below was computed BY HAND from the ROM contents
    // (wordle_rom.sv) using the exact spec rules:
    //   * GREEN: exact letter+position match; consumes that ref letter.
    //   * YELLOW: letter present elsewhere in the REMAINING ref; when several
    //             guess copies compete for one ref letter, the LAST (rightmost)
    //             copy wins (the "oval"/"boom" -> . . Y . rule).
    //   * GREY: everything else.
    // Packing (matches helloworld.c): letter 0 (leftmost) occupies the
    // MOST-significant 2 bits, o_result[7:6]; letter 3 occupies o_result[1:0].
    // So 8'bAABBCCDD reads left-to-right as letters 0,1,2,3 -- the same order
    // PuTTY prints them.
    // ROM words referenced (idx = word):
    //   0=skim 1=pare 2=cloy 3=corn 6=zonk 12=star 25=loll 28=full
    //   50=have 159=xray 195=gnaw
    // =====================================================================

    // --- Test 1: straight WIN (guess == ref) ---------------------------------
    // ref skim, guess skim -> G G G G, status WIN, count 1.
    start_game(10'd0);
    do_guess(str2word("skim"), 8'b01010101, WIN, 1'b1);
    check_count(7'd1);
    check_not_ready();                  // ready must stay low after WIN

    // --- Test 2: ALL-GREY (no letters in common) -----------------------------
    // ref xray, guess blob -> . . . ., ONGOING.
    start_game(10'd159);
    do_guess(str2word("blob"), 8'b00000000, ONGOING, 1'b1);

    // --- Test 3: mixed GREEN / YELLOW / GREY ---------------------------------
    // ref star, guess rate -> Y Y Y .  (r,a,t all present but misplaced; e absent)
    // letters 0..3 = Y,Y,Y,. -> bits [7:6]=10 [5:4]=10 [3:2]=10 [1:0]=00
    start_game(10'd12);
    do_guess(str2word("rate"), 8'b10101000, ONGOING, 1'b1);

    // --- Test 4: mostly GREEN, one GREY (single-letter diff) ------------------
    // ref have, guess gave -> . G G G  -> 8'b00010101
    start_game(10'd50);
    do_guess(str2word("gave"), 8'b00010101, ONGOING, 1'b0);

    // --- Test 5: duplicate letter in GUESS, GREEN consumes ref ---------------
    // ref loll, guess lull -> G . G G  (three l's align green; u is grey)
    // -> 8'b01000101
    start_game(10'd25);
    do_guess(str2word("lull"), 8'b01000101, ONGOING, 1'b0);

    // --- Test 6: LAST-OCCURRENCE yellow (marquee rule) ------------------------
    // ref corn has 'r' exactly once (pos2). guess rxxr: no greens on the r's;
    // only the LAST r (pos3) is yellow, the first (pos0) stays grey.
    //   slots: pos0 GREY, pos1 GREY, pos2 GREY, pos3 YELLOW -> 8'b00000010
    start_game(10'd3);
    do_guess(str2word("rxxr"), 8'b00000010, ONGOING, 1'b1);

    // --- Test 7: duplicate in REF, partial GREEN + grey ----------------------
    // ref loll, guess ullu -> . Y G .
    //   pos0 u(grey) pos1 l: not green(ref o), yellow from remaining ref l;
    //   pos2 l==l green(consume); pos3 u grey.  -> 8'b00100100
    start_game(10'd25);
    do_guess(str2word("ullu"), 8'b00100100, ONGOING, 1'b0);

    // --- Test 8: duplicate in BOTH ref and guess -----------------------------
    // ref full, guess lulu -> Y G G .
    //   pos0 l: ref l at pos2/3; not green -> yellow; pos1 u==u green;
    //   pos2 l==l green(consume one l); pos3 u: remaining ref has no u -> grey.
    //   -> 8'b10010100
    start_game(10'd28);
    do_guess(str2word("lulu"), 8'b10010100, ONGOING, 1'b0);

    // --- Test 9: all YELLOW-ish anagram-style -------------------------------
    // ref zonk, guess knob -> Y Y Y .
    //   k present(pos3 ref) misplaced; n present misplaced; o present misplaced;
    //   b absent. -> 8'b10101000
    start_game(10'd6);
    do_guess(str2word("knob"), 8'b10101000, ONGOING, 1'b1);

    // --- Test 10: LOSE -- exhaust all 6 guesses with wrong words -------------
    // ref skim; six 'xxxx' guesses -> all grey each; status LOSE on the 6th,
    // ONGOING before that; final count 6; ready stays low after LOSE.
    start_game(10'd0);
    do_guess(str2word("xxxx"), 8'b00000000, ONGOING, 1'b1);  // 1
    do_guess(str2word("xxxx"), 8'b00000000, ONGOING, 1'b1);  // 2
    do_guess(str2word("xxxx"), 8'b00000000, ONGOING, 1'b1);  // 3
    do_guess(str2word("xxxx"), 8'b00000000, ONGOING, 1'b1);  // 4
    do_guess(str2word("xxxx"), 8'b00000000, ONGOING, 1'b1);  // 5
    do_guess(str2word("xxxx"), 8'b00000000, LOSE,    1'b1);  // 6 -> LOSE
    check_count(7'd6);
    check_not_ready();

    // --- Test 11: WIN on a LATER guess (wrong, wrong, correct) ---------------
    // ref zonk; two wrong guesses then the correct word -> WIN on guess 3.
    start_game(10'd6);
    do_guess(str2word("aaaa"), 8'b00000000, ONGOING, 1'b1);  // 1, all grey
    do_guess(str2word("bbbb"), 8'b00000000, ONGOING, 1'b1);  // 2, all grey
    do_guess(str2word("zonk"), 8'b01010101, WIN,     1'b1);  // 3 -> WIN
    check_count(7'd3);
    check_not_ready();

    // --- Test 12: RESTART after a finished game (i_guess_id -> 0) ------------
    // start_game() drives i_guess_id back to 0, which the spec uses to begin a
    // new game after WIN/LOSE. Verify a brand-new game scores correctly again.
    // ref gnaw, guess wars -> Y Y . .
    //   gnaw letters g n a w; guess w a r s: w yellow, a yellow, r grey, s grey
    //   -> 8'b10100000
    start_game(10'd195);
    do_guess(str2word("wars"), 8'b10100000, ONGOING, 1'b1);
    check_count(7'd1);                   // counter reset for the new game

    // --- Test 13: another fresh WIN to confirm clean restart -----------------
    start_game(10'd12);
    do_guess(str2word("star"), 8'b01010101, WIN, 1'b1);
    check_count(7'd1);
    check_not_ready();

    // Report the per-check tally alongside the required PASS/FAIL line.
    $display("Checks correct: %0d / %0d", correct_results, total_checks);

    /******* Your code ends here ********/
   
    if (sim_failed) begin
        $display("TEST FAILED!");
    end else begin
        $display("TEST PASSED!");
    end
    $finish;
end
endmodule

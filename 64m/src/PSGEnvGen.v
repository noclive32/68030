/* ============================================================================
    (C) 2007  Robert Finch
	All rights reserved.

	PSGEnvGen.v
	Version 1.1

	ADSR envelope generator.

    This source code is available for evaluation and validation purposes
    only. This copyright statement and disclaimer must remain present in
    the file.

			 Motorola 68030
	Spartan3
	Webpack 9.1i xc3s1000-4ft256
	522 LUTs / 271 slices / 81.155 MHz (speed)
============================================================================ */

/*
	sample attack values / rates
	----------------------------
	8		2ms
	32		8ms
	64		16ms
	96		24ms
	152		38ms
	224		56ms
	272		68ms
	320		80ms
	400		100ms
	955		239ms
	1998	500ms
	3196	800ms
	3995	1s
	12784	3.2s
	21174	5.3s
	31960	8s

	rate = 990.00ns x 256 x value
*/


// envelope generator states
`define ENV_IDLE	0
`define ENV_ATTACK	1
`define ENV_DECAY	2
`define ENV_SUSTAIN	3
`define ENV_RELEASE	4

// Envelope generator
module PSGEnvGen(rst, clk, cnt,
	gate,
	attack0, attack1, attack2, attack3,
	decay0, decay1, decay2, decay3,
	sustain0, sustain1, sustain2, sustain3,
	relese0, relese1, relese2, relese3,
	o);
	parameter pChannels = 4;
	parameter pPrescalerBits = 8;
	input rst;							// reset
	input clk;							// core clock
	input [pPrescalerBits-1:0] cnt;		// clock rate prescaler
	input [15:0] attack0;
	input [15:0] attack1;
	input [15:0] attack2;
	input [15:0] attack3;
	input [11:0] decay0;
	input [11:0] decay1;
	input [11:0] decay2;
	input [11:0] decay3;
	input [7:0] sustain0;
	input [7:0] sustain1;
	input [7:0] sustain2;
	input [7:0] sustain3;
	input [11:0] relese0;
	input [11:0] relese1;
	input [11:0] relese2;
	input [11:0] relese3;
	input [3:0] gate;
	output [7:0] o;

	reg [7:0] sustain;
	reg [15:0] attack;
	reg [17:0] decay;
	reg [17:0] relese;
	// Per channel count storage
	reg [7:0] envCtr [3:0];
	reg [7:0] envCtr2 [3:0];
	reg [7:0] iv [3:0];			// interval value for decay/release
	reg [2:0] icnt [3:0];		// interval count
	reg [19:0] envDvn [3:0];
	reg [2:0] envState [3:0];

	reg [2:0] envStateNxt;
	reg [15:0] envStepPeriod;	// determines the length of one step of the envelope generator
	reg [7:0] envCtrx;
	reg [19:0] envDvnx;

	// Time multiplexed values
	wire [15:0] attack_x;
	wire [11:0] decay_x;
	wire [7:0] sustain_x;
	wire [11:0] relese_x;

	integer n;

    wire [1:0] sel = cnt[1:0];

	mux4to1 #(16) u1 (
		.e(1'b1),
		.s(sel),
		.i0(attack0),
		.i1(attack1),
		.i2(attack2),
		.i3(attack3),
		.z(attack_x)
	);

	mux4to1 #(12) u2 (
		.e(1'b1),
		.s(sel),
		.i0(decay0),
		.i1(decay1),
		.i2(decay2),
		.i3(decay3),
		.z(decay_x)
	);

	mux4to1 #(8) u3 (
		.e(1'b1),
		.s(sel),
		.i0(sustain0),
		.i1(sustain1),
		.i2(sustain2),
		.i3(sustain3),
		.z(sustain_x)
	);

	mux4to1 #(12) u4 (
		.e(1'b1),
		.s(sel),
		.i0(relese0),
		.i1(relese1),
		.i2(relese2),
		.i3(relese3),
		.z(relese_x)
	);

	always @(attack_x)
		attack <= attack_x;

	always @(decay_x)
		decay <= decay_x;

	always @(sustain_x)
		sustain <= sustain_x;

	always @(relese_x)
		relese <= relese_x;


	always @(sel)
		envCtrx <= envCtr[sel];

	always @(sel)
		envDvnx <= envDvn[sel];


	// Envelope generate state machine
	// Determine the next envelope state
	always @(sel or gate or sustain)
	begin
		case (envState[sel])
		`ENV_IDLE:
			if (gate[sel])
				envStateNxt <= `ENV_ATTACK;
			else
				envStateNxt <= `ENV_IDLE;
		`ENV_ATTACK:
			if (envCtrx==8'hFE) begin
				if (sustain==8'hFF)
					envStateNxt <= `ENV_SUSTAIN;
				else
					envStateNxt <= `ENV_DECAY;
			end
			else
				envStateNxt <= `ENV_ATTACK;
		`ENV_DECAY:
			if (envCtrx==sustain)
				envStateNxt <= `ENV_SUSTAIN;
			else
				envStateNxt <= `ENV_DECAY;
		`ENV_SUSTAIN:
			if (~gate[sel])
				envStateNxt <= `ENV_RELEASE;
			else
				envStateNxt <= `ENV_SUSTAIN;
		`ENV_RELEASE: begin
			if (envCtrx==8'h00)
				envStateNxt <= `ENV_IDLE;
			else if (gate[sel])
				envStateNxt <= `ENV_SUSTAIN;
			else
				envStateNxt <= `ENV_RELEASE;
			end
		// In case of hardware problem
		default:
			envStateNxt <= `ENV_IDLE;
		endcase
	end

	always @(posedge clk)
		if (rst) begin
		    for (n = 0; n < pChannels; n = n + 1)
		        envState[n] <= `ENV_IDLE;
		end
		else if (cnt < pChannels)
			envState[sel] <= envStateNxt;


	// Handle envelope counter
	always @(posedge clk)
		if (rst) begin
		    for (n = 0; n < pChannels; n = n + 1) begin
		        envCtr[n] <= 0;
		        envCtr2[n] <= 0;
		        icnt[n] <= 0;
		        iv[n] <= 0;
		    end
		end
		else if (cnt < pChannels) begin
			case (envState[sel])
			`ENV_IDLE:
				begin
				envCtr[sel] <= 0;
				envCtr2[sel] <= 0;
				icnt[sel] <= 0;
				iv[sel] <= 0;
				end
			`ENV_SUSTAIN:
				begin
				envCtr2[sel] <= 0;
				icnt[sel] <= 0;
				iv[sel] <= sustain >> 3;
				end
			`ENV_ATTACK:
				begin
				icnt[sel] <= 0;
				iv[sel] <= (8'hff - sustain) >> 3;
				if (envDvnx==20'h0) begin
					envCtr2[sel] <= 0;
					envCtr[sel] <= envCtrx + 1;
				end
				end
			`ENV_DECAY,
			`ENV_RELEASE:
				if (envDvnx==20'h0) begin
					envCtr[sel] <= envCtrx - 1;
					if (envCtr2[sel]==iv[sel]) begin
						envCtr2[sel] <= 0;
						if (icnt[sel] < 3'd7)
							icnt[sel] <= icnt[sel] + 1;
					end
					else
						envCtr2[sel] <= envCtr2[sel] + 1;
				end
			endcase
		end

	// Determine envelope divider adjustment source
	always @(sel or attack or decay or relese)
	begin
		case(envState[sel])
		`ENV_ATTACK:	envStepPeriod <= attack;
		`ENV_DECAY:		envStepPeriod <= decay;
		`ENV_RELEASE:	envStepPeriod <= relese;
		default:		envStepPeriod <= 16'h0;
		endcase
	end


	// double the delay at appropriate points
	// for exponential modelling
	wire [19:0] envStepPeriod1 = {4'b0,envStepPeriod} << icnt[sel];


	// handle the clock divider
	// loadable down counter
	// This sets the period of each step of the envelope
	always @(posedge clk)
		if (rst) begin
			for (n = 0; n < pChannels; n = n + 1)
				envDvn[n] <= 0;
		end
		else if (cnt < pChannels) begin
			if (envDvnx==20'h0)
				envDvn[sel] <= envStepPeriod1;
			else
				envDvn[sel] <= envDvnx - 1;
		end

	assign o = envCtrx;

endmodule



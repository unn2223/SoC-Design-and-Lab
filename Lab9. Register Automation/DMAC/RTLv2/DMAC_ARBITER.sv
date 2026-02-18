// Copyright (c) 2021 Sungkyunkwan University
//
// Authors:
// - Jungrae Kim <dale40@skku.edu>

module DMAC_ARBITER
#(
    parameter N_MASTER    = 4,
    parameter DATA_SIZE   = 32
)
(
    input   wire                clk,
    input   wire                rst_n,  // _n means active low

    // configuration registers
    input   wire                src_valid_i[N_MASTER],
    output  reg                 src_ready_o[N_MASTER],
    input   wire    [DATA_SIZE-1:0]     src_data_i[N_MASTER],

    output  reg                 dst_valid_o,
    input   wire                dst_ready_i,
    output  reg     [DATA_SIZE-1:0] dst_data_o
);
    
    // [Round Robin Pointer]
    reg [1:0]  priority_idx; 
    
    // [Current Winner Index]
    reg [1:0]  grant_idx;
    
    // [Lock Status]
    reg        is_locked;
    reg [1:0]  locked_idx;

    // [Magic Flag]
    wire last_flag;
    assign last_flag = src_data_i[grant_idx][0]; 

    //----------------------------------------------------------
    // 1. Winner Selection Logic
    //----------------------------------------------------------
    always_comb begin
        integer i;
        reg [1:0] idx; // 여기도 2비트로 고정

        // 락이 걸려있으면 -> 잡고 있는 놈이 계속 주인
        if (is_locked) begin
            grant_idx = locked_idx;
        end
        // 락이 없으면 -> 우선순위 포인터부터 Round-Robin 탐색
        else begin
            grant_idx = priority_idx; // default
            for (i = 0; i < N_MASTER; i = i + 1) begin
                idx = (priority_idx + i) % N_MASTER;
                if (src_valid_i[idx]) begin
                    grant_idx = idx;
                    break;
                end
            end
        end
    end

    //----------------------------------------------------------
    // 2. Output Muxing Logic
    //----------------------------------------------------------
    always_comb begin
        integer i;
        
        // Winner의 신호를 출력으로 연결
        dst_valid_o = src_valid_i[grant_idx];
        dst_data_o  = src_data_i[grant_idx];

        // Winner에게만 Ready 신호 전달
        for (i = 0; i < N_MASTER; i = i + 1) begin
            if (i == grant_idx) 
                src_ready_o[i] = dst_ready_i;
            else
                src_ready_o[i] = 1'b0;
        end
    end

    //----------------------------------------------------------
    // 3. Update Logic (Priority & Lock)
    //----------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priority_idx <= 2'd0;
            is_locked    <= 1'b0;
            locked_idx   <= 2'd0;
        end
        else begin
            // Handshake (전송 성공) 발생 시
            if (dst_valid_o && dst_ready_i) begin
                
                // 마지막 비트(last_flag)가 1이면? (WLAST 혹은 AW/AR 명령)
                if (last_flag) begin
                    // 버스트 종료 (혹은 단일 명령 종료) -> Lock 해제 & 다음 사람에게 우선권
                    is_locked    <= 1'b0;
                    priority_idx <= (grant_idx + 2'd1) % N_MASTER;
                end 
                else begin
                    // 마지막이 아님 (W 채널 버스트 진행 중) -> Lock 걸기
                    is_locked    <= 1'b1;
                    locked_idx   <= grant_idx;
                    // 우선순위는 유지 (Lock 풀릴 때 넘김)
                end
            end
        end
    end

endmodule
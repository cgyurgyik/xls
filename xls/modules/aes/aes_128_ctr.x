// Copyright 2022 The XLS Authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Implements the AES-128 CTR mode cipher.
// TODO(rspringer): Allow wider msg interface (parameterizable?).
import std
import xls.modules.aes.aes_128
import xls.modules.aes.aes_128_common

type Block = aes_128_common::Block;
type Key = aes_128_common::Key;
type InitVector = uN[96];

// The command sent to the encoding proc at the beginning of processing.
struct Command {
    // The number of bytes to expect in the incoming message.
    // At present, this number must be a multiple of 128.
    msg_bytes: u32,

    // The encryption key.
    key: Key,

    // The initialization vector for the operation.
    iv: InitVector,
}

// The current FSM state of the encoding block.
enum Step : bool {
  IDLE = 0,
  PROCESSING = 1,
}

// The recurrent state of the proc.
struct State {
  step: Step,
  command: Command,
  ctr: uN[32],
  blocks_left: uN[32],
}

// Performs the actual work of encrypting (or decrypting!) a block in CTR mode.
fn aes_128_ctr_encrypt(key: Key, ctr: uN[128], block: Block) -> Block {
    // TODO(rspringer): Avoid the need for this two-step type conversion.
    let ctr_array = ctr as u32[4];
    let ctr_enc = aes_128::aes_encrypt(
        key,
        Block:[
            ctr_array[0] as u8[4],
            ctr_array[1] as u8[4],
            ctr_array[2] as u8[4],
            ctr_array[3] as u8[4]
        ]);
    Block:[
        ((ctr_enc[0] as u32) ^ (block[0] as u32)) as u8[4],
        ((ctr_enc[1] as u32) ^ (block[1] as u32)) as u8[4],
        ((ctr_enc[2] as u32) ^ (block[2] as u32)) as u8[4],
        ((ctr_enc[3] as u32) ^ (block[3] as u32)) as u8[4],
    ]
}

// Note that encryption and decryption are the _EXACT_SAME_PROCESS_!
proc aes_128_ctr {
    command_in: chan in Command;
    ptxt_in: chan in Block;
    ctxt_out: chan out Block;

    config(command_in: chan in Command,
           ptxt_in: chan in Block, ctxt_out: chan out Block) {
        (command_in, ptxt_in, ctxt_out)
    }

    next(tok: token, state: State) {
        let step = state.step;

        let (tok, cmd) = recv_if(tok, command_in, step == Step::IDLE);
        let cmd = if step == Step::IDLE { cmd } else { state.command };
        let ctr = if step == Step::IDLE { u32:0 } else { state.ctr };
        let full_ctr = cmd.iv ++ ctr;

        // TODO(rspringer): Only recv if cmd specifies non-zero blocks!
        let (tok, block) = recv(tok, ptxt_in);
        let ctxt = aes_128_ctr_encrypt(cmd.key, full_ctr, block);
        let tok = send(tok, ctxt_out, ctxt);

        let blocks_left =
            if step == Step::IDLE { std::ceil_div(cmd.msg_bytes, u32:16) - u32:1 }
            else { state.blocks_left - u32:1 };
        let step = if blocks_left == u32:0 { Step::IDLE } else { Step::PROCESSING };

        // We don't have to worry about ctr overflowing (which would result in an
        // invalid encryption, since ctr starts at zero, and the maximum possible
        // number of blocks per command is 2^32 - 1.
        State { step: step, command: cmd, ctr: ctr + u32:1, blocks_left: blocks_left }
    }
}

#![test_proc()]
proc aes_128_ctr_test {
    terminator: chan out bool;

    command_out: chan out Command;
    ptxt_out: chan out Block;
    ctxt_in: chan in Block;

    config(terminator: chan out bool) {
        let (command_in, command_out) = chan Command;
        let (ptxt_in, ptxt_out) = chan Block;
        let (ctxt_in, ctxt_out) = chan Block;

        let init_state = State {
            step: Step::IDLE,
            command: Command {
                msg_bytes: u32:0,
                key: Key:[ u32:0, u32:0, u32:0, u32:0 ],
                iv: InitVector:0,
            },
            ctr: uN[32]:0,
            blocks_left: u32:0,
        };

        spawn aes_128_ctr(command_in, ptxt_in, ctxt_out)(init_state);
        (terminator, command_out, ptxt_out, ctxt_in)
    }

    next(tok: token) {
        let key = Key:[
            u8:0x00 ++ u8:0x01 ++ u8:0x02 ++ u8:0x03,
            u8:0x04 ++ u8:0x05 ++ u8:0x06 ++ u8:0x07,
            u8:0x08 ++ u8:0x09 ++ u8:0x0a ++ u8:0x0b,
            u8:0x0c ++ u8:0x0d ++ u8:0x0e ++ u8:0x0f,
        ];
        let iv = u8[12]:[
            u8:0x10, u8:0x11, u8:0x12, u8:0x13,
            u8:0x14, u8:0x15, u8:0x16, u8:0x17,
            u8:0x18, u8:0x19, u8:0x1a, u8:0x1b,
        ] as InitVector;
        let cmd = Command {
            msg_bytes: u32:32,
            key: key,
            iv: iv,
        };
        let tok = send(tok, command_out, cmd);

        let plaintext_0 = Block:[
            u8[4]:[u8:0x20, u8:0x21, u8:0x22, u8:0x23],
            u8[4]:[u8:0x24, u8:0x25, u8:0x26, u8:0x27],
            u8[4]:[u8:0x28, u8:0x29, u8:0x2a, u8:0x2b],
            u8[4]:[u8:0x2c, u8:0x2d, u8:0x2e, u8:0x2f],
        ];
        let tok = send(tok, ptxt_out, plaintext_0);
        let (tok, ctxt) = recv(tok, ctxt_in);
        let expected = Block:[
            u8[4]:[u8:0x27, u8:0x6a, u8:0xec, u8:0x41],
            u8[4]:[u8:0xfd, u8:0xa9, u8:0x9f, u8:0x26],
            u8[4]:[u8:0x34, u8:0xc5, u8:0x43, u8:0x73],
            u8[4]:[u8:0xc7, u8:0x99, u8:0xd2, u8:0x19],
        ];
        let _ = assert_eq(ctxt, expected);

        let plaintext_1 = Block:[
            u8[4]:[u8:0x30, u8:0x31, u8:0x32, u8:0x33],
            u8[4]:[u8:0x34, u8:0x35, u8:0x36, u8:0x37],
            u8[4]:[u8:0x38, u8:0x39, u8:0x3a, u8:0x3b],
            u8[4]:[u8:0x3c, u8:0x3d, u8:0x3e, u8:0x3f],
        ];
        let tok = send(tok, ptxt_out, plaintext_1);
        let (tok, ctxt) = recv(tok, ctxt_in);
        let expected = Block:[
            u8[4]:[u8:0x3e, u8:0xe6, u8:0x17, u8:0xa9],
            u8[4]:[u8:0xe9, u8:0x25, u8:0x27, u8:0xd6],
            u8[4]:[u8:0x61, u8:0xe9, u8:0x34, u8:0x5a],
            u8[4]:[u8:0x8d, u8:0xaf, u8:0x6a, u8:0x2f],
        ];
        let _ = assert_eq(ctxt, expected);

        // Command #2.
        let cmd = Command {
            msg_bytes: u32:16,
            key: key,
            iv: iv,
        };

        let tok = send(tok, command_out, cmd);
        let plaintext_0 = Block:[
            u8[4]:[u8:0x20, u8:0x21, u8:0x22, u8:0x23],
            u8[4]:[u8:0x24, u8:0x25, u8:0x26, u8:0x27],
            u8[4]:[u8:0x28, u8:0x29, u8:0x2a, u8:0x2b],
            u8[4]:[u8:0x2c, u8:0x2d, u8:0x2e, u8:0x2f],
        ];
        let tok = send(tok, ptxt_out, plaintext_0);
        let (tok, ctxt) = recv(tok, ctxt_in);
        let expected = Block:[
            u8[4]:[u8:0x27, u8:0x6a, u8:0xec, u8:0x41],
            u8[4]:[u8:0xfd, u8:0xa9, u8:0x9f, u8:0x26],
            u8[4]:[u8:0x34, u8:0xc5, u8:0x43, u8:0x73],
            u8[4]:[u8:0xc7, u8:0x99, u8:0xd2, u8:0x19],
        ];
        let _ = assert_eq(ctxt, expected);

        // Now test decryption! Just do a single block.
        let cmd = Command {
            msg_bytes: u32:16,
            key: key,
            iv: iv,
        };
        let tok = send(tok, command_out, cmd);
        let ciphertext_0 = Block:[
            u8[4]:[u8:0x27, u8:0x6a, u8:0xec, u8:0x41],
            u8[4]:[u8:0xfd, u8:0xa9, u8:0x9f, u8:0x26],
            u8[4]:[u8:0x34, u8:0xc5, u8:0x43, u8:0x73],
            u8[4]:[u8:0xc7, u8:0x99, u8:0xd2, u8:0x19],
        ];
        let tok = send(tok, ptxt_out, ciphertext_0);
        let (tok, ptxt) = recv(tok, ctxt_in);
        let expected = Block:[
            u8[4]:[u8:0x20, u8:0x21, u8:0x22, u8:0x23],
            u8[4]:[u8:0x24, u8:0x25, u8:0x26, u8:0x27],
            u8[4]:[u8:0x28, u8:0x29, u8:0x2a, u8:0x2b],
            u8[4]:[u8:0x2c, u8:0x2d, u8:0x2e, u8:0x2f],
        ];
        let _ = assert_eq(ptxt, expected);

        let tok = send(tok, terminator, true);
        ()
    }
}

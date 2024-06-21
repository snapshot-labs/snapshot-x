// Draft code for verifying Bitcoin signature

use alexandria_data_structures::byte_appender::ByteAppender;
use core::byte_array::ByteArrayTrait;
use core::option::OptionTrait;
use core::array::ArrayTrait;
use alexandria_data_structures::array_ext::ArrayTraitExt;
use starknet::{EthAddress, SyscallResultTrait};
use starknet::secp256_trait::{
    Signature, recover_public_key, Secp256PointTrait, signature_from_vrs, is_valid_signature
};
use starknet::secp256k1::{Secp256k1Point};
use starknet::eth_signature::verify_eth_signature;
use core::traits::{Into, TryInto};
use alexandria_bytes::{Bytes, BytesTrait};
use alexandria_encoding::sol_abi::decode::SolAbiDecodeTrait;
use alexandria_encoding::sol_abi::decode::SolAbiDecodeBytes;
use starknet::{ContractAddress};
use alexandria_encoding::base64::{Base64Encoder, Base64Decoder, Base64UrlEncoder, Base64UrlDecoder};

use alexandria_math::{sha256, fast_power};

mod ripemd;

fn hash(input: u256, prefix: u8) -> Array<u8> {
    let mut mutable = input.clone();
    let mut input_arr = array![];
    let mut i: usize = 0;

    // convert u256 to Array<u8>
    loop {
        if mutable == 0 {
            break;
        }
        let hmm = mutable % 256;
        let aa: u8 = hmm.try_into().expect('number too big for hashing');
        input_arr.append(aa);
        mutable /= 256;
        i += 1;
    };
    input_arr.append(prefix);
    let shad = sha256::sha256(input_arr.reversed());
    shad
}

fn u8_array_to_u256(input: Array<u8>) -> u256 {
    let mut result: u256 = 0;

    // Concatenate bytes into felt252
    let mut i = 0;
    while (i < 32 && i < input.len()) {
        result = result * 256 + (*input[i]).into(); // Assuming big-endian byte order
        i = i + 1;
    };
    return result;
}

fn print_array(array: Array<u8>) {
    let mut str: ByteArray = "";

    let mut i: usize = 0;
    loop {
        str.append_byte(*array[i]);
        if i == array.len() - 1 {
            break;
        }
        i += 1;
    };
    println!("{}", str);
}

fn print_bin_array(array: Array<u8>) {
    let conv = u8_array_to_hex(array);
    let mut str: ByteArray = "";

    let mut i: usize = 0;
    loop {
        //print!("{} ", array[i]);
        //let dip = *array[i];
        str.append_byte(*conv[i]);
        //str.append_word(dip,);
        if i == conv.len() - 1 {
            break;
        }
        i += 1;
    };
    println!("{}", str);
}

// Function to convert an array of u8 to a hexadecimal string
fn u8_array_to_hex(arr: Array<u8>) -> Array<u8> {
    let mut hex_str: Array<u8> = array![];
    let mut i: usize = 0;
    loop {
        if i >= arr.len() {
            break;
        }
        let (high_char, low_char) = u8_to_hex(*arr[i]);
        hex_str.append(high_char);
        hex_str.append(low_char);
        i += 1;
    };

    return hex_str;
}

fn u8_to_hex(val: u8) -> (u8, u8) {
    // Lookup table for hexadecimal characters
    let hex_chars: Array<u8> = array![
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
    ];

    // Get the high nibble (4 bits) and the low nibble (4 bits)
    let high_nibble: usize = (val / 16).into();
    let low_nibble: usize = (val % 16).into();

    // Map the nibbles to their corresponding hex characters
    let high_char = hex_chars.at(high_nibble);
    let low_char = hex_chars.at(low_nibble);

    return (*high_char, *low_char);
}

fn base58(input: felt252) -> Array<u8> {
    let base58_alphabet: Array<u8> = array![
        0x31,
        0x32,
        0x33,
        0x34,
        0x35,
        0x36,
        0x37,
        0x38,
        0x39,
        0x41,
        0x42,
        0x43,
        0x44,
        0x45,
        0x46,
        0x47,
        0x48,
        0x4a,
        0x4b,
        0x4c,
        0x4d,
        0x4e,
        0x50,
        0x51,
        0x52,
        0x53,
        0x54,
        0x55,
        0x56,
        0x57,
        0x58,
        0x59,
        0x5a,
        0x61,
        0x62,
        0x63,
        0x64,
        0x65,
        0x66,
        0x67,
        0x68,
        0x69,
        0x6a,
        0x6b,
        0x6d,
        0x6e,
        0x6f,
        0x70,
        0x71,
        0x72,
        0x73,
        0x74,
        0x75,
        0x76,
        0x77,
        0x78,
        0x79,
        0x7a
    ];

    let mut encoded: Array<u8> = array![];
    let mut remainder: u256 = 0;
    let mut char_index: u32 = 0;
    let mut number: u256 = input.into();
    let base: u256 = 58;

    loop {
        remainder = number % base;
        number = number / base;
        char_index = remainder.try_into().expect('something fluffy happened');
        //println!("Appending {}", char_index);
        encoded.append(*base58_alphabet.at(char_index));
        if number == 0 {
            break;
        }
    };
    encoded = encoded.reversed();
    encoded
}

fn double_hash(mut input: u256) -> Array<u8> {
    let mut input_arr2: Array<u8> = array![];
    let mut i2: usize = 0;
    //print!("PRE ");
    loop {
        if input == 0 {
            break;
        }
        let hmm = input % 256;
        let aa: u8 = hmm.try_into().expect('number too big for hashing');
        input_arr2.append(aa);
        //print!("{} ", aa);
        input /= 256;
        i2 += 1;
    };
    // println!("");
    input_arr2 = input_arr2.reversed();

    // Do hashing
    let hash1 = sha256::sha256(input_arr2); //hash(versioned.into(), 0);
    let hash2 = sha256::sha256(hash1);
    hash2
}

fn ripe(input: Array<u8>) -> felt252 {
    // TODO: find an implementation

    if (*input[0] == 0xf3) {
        // f35258d64035912d83d363a0a3076b403e579bcde8785b073a4e6157507eb93d ->
        return 0x79f574bd245e676a25b11a81cb53838da522150b;
    } else if (*input[0] == 0x37) {
        // 3757c502531d6f260fa38cd72b05562feb9d709aeb53db93f2e62fb23b15158d ->
        return 0xd96d7d329a97d31eacb6fdc07e019b8a6854d95c;
    } else if (*input[0] == 0x07) {
        // 070b25d52ca97f22ddfce334b12e45bfba3fefee25edbe716f22a6df0afd131b -> 
        return 0xaebb1673edbc48bb3ac99077fdf5b15941a788b8;
    } else if (*input[0] == 0x87) {
        // 87da5b3f682208667d326418a68dc9ecf08f330513a44ac955441fe8afaff207 ->
        return 0x1b815806a318617073e748a4cd88a2d7874ae2d7;
    } else if (*input[0] == 0x66) {
        // 66245d9b0b0003feb7e1d36f83e4c734a2bb7983fc6cfb02abdc031e4fe71a2a ->
        return 0x58263265cff2280d4b78d94b6f3790acc407afc7;
    } else if (*input[0] == 0xa1) {
        // a16c146b85945b1a3d0de167ea5aef584c5df12681eff0c664b2e31b2a200525 ->
        return 0x607947c0abf8804765f14330882be561f30610d3;
    } else if (*input[0] == 0xab) {
        // abe83a391095ac878d043164bd8bac346740ab231a666779f28c71c66a53fa09 ->
        return 0xc7d7fe3ab40310cd751e2f2a76ca002648208249;
    } else if (*input[0] == 0x6a) {
        // 6ada8311778fc2a4e7471cd3bd47ecafd01be1b05e0b227b928df89b1678b337 ->
        return 0xacced0c839896a7104e2de7fc08a7683577923ed;
    }
    // Avoid errors with unreachable code
    if (1 == 1) {
        panic!("No ripe for {}", *input[0]);
    }
    return 1;
}

fn print_hex(input: felt252) {
    let hex_chars: Array<u8> = array![
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
    ];

    // Extract each digit and map to hex character
    let mut temp: u256 = input.into();
    let mut str: ByteArray = "";

    loop {
        let digit: u256 = temp.into() % 16;
        temp = temp / 16;
        let digit_u: usize = digit.try_into().expect('Too big numbers');

        str.append_byte(*hex_chars[digit_u]);

        if temp == 0 {
            break;
        }
    };

    println!("{}", str.rev());
}

fn print_hex_u256(input: u256) {
    let hex_chars: Array<u8> = array![
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'
    ];

    // Extract each digit and map to hex character
    let mut temp: u256 = input.into();
    let mut str: ByteArray = "";

    loop {
        let digit: u256 = temp.into() % 16;
        temp = temp / 16;
        let digit_u: usize = digit.try_into().expect('Too big numbers');

        str.append_byte(*hex_chars[digit_u]);

        if temp == 0 {
            break;
        }
    };

    println!("{}", str.rev());
}

fn string_to_array_u8(base64_str: ByteArray) -> Array<u8> {
    // Calculate the length of the base64 string
    let base64_str_len = base64_str.len();

    // Allocate an array for the bytes
    let mut byte_array: Array<u8> = array![];

    // Iterate through the base64 string and convert each character to a byte
    let mut i: usize = 0;
    while i < base64_str_len {
        let char_byte = base64_str[i];
        byte_array.append(char_byte);
        i = i + 1;
    };

    return byte_array;
}

fn get_msg_hash(msg_orig: ByteArray) -> Array<u8> {
    let prefix_orig: ByteArray = "\u0018Bitcoin Signed Message:\n";

    let msg = string_to_array_u8(msg_orig);
    let prefix = string_to_array_u8(prefix_orig);

    // https://github.com/bitcoinjs/varuint-bitcoin/blob/8342fe7362f20a412d61b9ade20839aafaa7f78e/index.js#L79
    let mut encoding_length = 0;
    if (msg.len() < 0xfd) {
        encoding_length = 1;
    } else if (msg.len() < 0xffff) {
        encoding_length = 3;
    } else if (msg.len() < 0xffffffff) {
        encoding_length = 5;
    } else {
        encoding_length = 9;
    }

    let mut buffer: Array<u8> = prefix;

    buffer.append(msg.len().try_into().expect('Weird'));
    buffer = buffer.concat(@msg);

    let res = sha256::sha256(sha256::sha256(buffer));
    res
}

fn calculate_address(msg: ByteArray, orig_signature: Array<u8>) -> Array<u8> {
    let msg_hash = get_msg_hash(msg);

    let v: u8 = *orig_signature[0];
    let mut r: Array<u8> = array![];
    let mut s: Array<u8> = array![];

    // LEN = 65

    let mut i = 1;
    while i < orig_signature
        .len() {
            if (i < 33) {
                r.append(*orig_signature[i]);
            } else {
                s.append(*orig_signature[i]);
            }

            i = i + 1;
        };

    let v_arr: Array<u8> = array![v];
    print!("DATA V "); // 36
    print_bin_array(v_arr);
    print!("DATA R ");
    print_bin_array(r.clone());
    print!("DATA S ");
    print_bin_array(s.clone());
    //println!("LENS {} {}", r.len(), s.len());

    // FIXME unsure about parity
    let sig: Signature = Signature {
        r: u8_array_to_u256(r), s: u8_array_to_u256(s), y_parity: (v % 2 == 0)
    };

    let a = u8_array_to_u256(msg_hash);

    let public_key = recover_public_key::<Secp256k1Point>(a, sig).unwrap();

    let (mut x, y) = public_key.get_coordinates().unwrap_syscall();
    print!("X ");
    println!("hmm {} ", x);
    print_hex_u256(x);
    print!("y ");
    print_hex_u256(y);

    let mut prefix: u8 = 2;
    if (y % 2 == 1) {
        prefix = 3;
    }

    // compressed key: 03e518c775fed4f868c5893ac8019b0871992fbf072be8faa0d63ec57cc7e61159

    // Compressed public key
    let shad = hash(x, prefix);
    print!("HASHED "); // 070b25d52ca97f22ddfce334b12e45bfba3fefee25edbe716f22a6df0afd131b
    print_bin_array(shad.clone());

    let riped: felt252 = ripe(shad);
    print!("RIPED ",);
    print_hex(riped); // aebb1673edbc48bb3ac99077fdf5b15941a788b8

    let shift = (20 * fast_power::fast_power(16_u256, 40_u256));
    let redeemed = shift.try_into().expect('number too big') + riped;
    print!("REDEEMED ");
    print_hex(redeemed); // 14aebb1673edbc48bb3ac99077fdf5b15941a788b8

    let hashed: u256 = redeemed.into();
    let aa = hash(hashed, 0x00);
    print!("HASHED "); // 87da5b3f682208667d326418a68dc9ecf08f330513a44ac955441fe8afaff207
    print_bin_array(aa.clone());

    let ripeResult = ripe(aa);
    print!("RIPED "); // 1b815806a318617073e748a4cd88a2d7874ae2d7
    print_hex(ripeResult);

    let bit_shift = (5 * fast_power::fast_power(16_u256, 40_u256));
    let versioned = bit_shift.try_into().expect('number too big') + ripeResult;

    print!("VERSIONED ");
    print_hex(versioned); // 51b815806a318617073e748a4cd88a2d7874ae2d7

    let mut mutable: u256 = versioned.into().clone();
    let hash2 = double_hash(mutable);

    // encode

    let mut concatenated_result: felt252 = 0;
    let byte1: felt252 = (*hash2[0]).into();
    let byte2: felt252 = (*hash2[1]).into();
    let byte3: felt252 = (*hash2[2]).into();
    let byte4: felt252 = (*hash2[3]).into();

    concatenated_result = (byte1 * fast_power::fast_power(256_u128, 3_u128).into())
        + (byte2 * fast_power::fast_power(256_u128, 2_u128).into())
        + (byte3 * fast_power::fast_power(256_u128, 1_u128).into())
        + (byte4 * fast_power::fast_power(256_u128, 0_u128).into())
        + (versioned * fast_power::fast_power(256_u128, 4_u128).into());

    print!("CHECKSUMMED ");

    print_hex(concatenated_result);

    let encoded = base58(concatenated_result);

    print!("Address: ");
    print_array(encoded.clone());
    println!("");
    encoded
}

#[test]
fn test_sig_verification() {
    // Should use: ECDSA verification, P2WPKH-P2SH compressed address

    // Signature for Hello World from wallet
    let orig_signature: Array<u8> = array![
        0x24,
        0x37,
        0x1a,
        0xff,
        0x24,
        0x98,
        0x2f,
        0x04,
        0x40,
        0xb6,
        0x75,
        0x94,
        0x94,
        0xf3,
        0xeb,
        0xb8,
        0xd8,
        0x32,
        0xa5,
        0x16,
        0x36,
        0xea,
        0x98,
        0x8e,
        0x00,
        0x91,
        0x9f,
        0x83,
        0xca,
        0x16,
        0x68,
        0x19,
        0x1b,
        0x46,
        0x3a,
        0x4a,
        0x68,
        0x14,
        0xa4,
        0x64,
        0x32,
        0xd5,
        0xf8,
        0xe2,
        0x9a,
        0x7d,
        0xab,
        0xb4,
        0x38,
        0xdf,
        0x02,
        0x08,
        0x7a,
        0xb3,
        0x4e,
        0xc4,
        0x5d,
        0x83,
        0x08,
        0xb6,
        0x1e,
        0xa5,
        0x5e,
        0x03,
        0x56
    ]; // 0x24371aff24982f440b6759494f3ebb8d832a51636ea988e0919f83ca1668191b463a4a6814a46432d5f8e29a7dabb438df287ab34ec45d838b61ea55e356

    let msg: ByteArray = "Hello World";
    calculate_address(msg, orig_signature);
}
//  verify_eth_signature(:msg_hash, :signature, :eth_address);
// 
// priv: 3af4ba068b2a5df595ec95f992a87597ee4366b8e15da91089a265a252a6abfd
// pub compressed: 03ffd665e11c73cfc92b2200ee28315ddd7aea485cb55d1eb62e53b15d3be521ef
// sha'd: f35258d64035912d83d363a0a3076b403e579bcde8785b073a4e6157507eb93d
// ripe'd: 79f574bd245e676a25b11a81cb53838da522150b

// legacy:
// add zeros: 0079f574bd245e676a25b11a81cb53838da522150b
// base58 plus check'd: 1C7roo4QqzgCWnCx7QMN5SNdE1vUFsJCRt

// P2SH (segwit):
// from ripe'd to redeemed: 001479f574bd245e676a25b11a81cb53838da522150b
// sha'd: 3757c502531d6f260fa38cd72b05562feb9d709aeb53db93f2e62fb23b15158d
// ripe'd: d96d7d329a97d31eacb6fdc07e019b8a6854d95c
// versioned: 05d96d7d329a97d31eacb6fdc07e019b8a6854d95c
// encoded: 3MWfibyH3KVEvg1JEnjzn2DUDhbgYm3ceu



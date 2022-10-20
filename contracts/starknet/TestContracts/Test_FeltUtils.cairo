%lang starknet
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.cairo_builtins import BitwiseBuiltin
from contracts.starknet.lib.math_utils import MathUtils

@view
func testWordsToUint256{range_check_ptr}(word1: felt, word2: felt, word3: felt, word4: felt) -> (
    uint256: Uint256
) {
    let (uint256) = MathUtils.words_to_uint256(word1, word2, word3, word4);
    return (uint256,);
}

@view
func testPackFelt{range_check_ptr}(num1: felt, num2: felt, num3: felt, num4: felt) -> (
    packed: felt
) {
    let (packed) = MathUtils.pack_4_32_bit(num1, num2, num3, num4);
    return (packed,);
}

@view
func testUnpackFelt{range_check_ptr, bitwise_ptr: BitwiseBuiltin*}(packed: felt) -> (
    num1: felt, num2: felt, num3: felt, num4: felt
) {
    alloc_locals;
    let (num1, num2, num3, num4) = MathUtils.unpack_4_32_bit(packed);
    return (num1, num2, num3, num4);
}

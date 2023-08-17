use option::OptionTrait;
use serde::Serde;
use clone::Clone;
use array::ArrayTrait;
use sx::utils::math;

#[derive(Option, Clone, Drop, Serde)]
struct IndexedStrategy {
    index: u8,
    params: Array<felt252>,
}

trait IndexedStrategyTrait {
    fn assert_no_duplicate_indices(self: @Array<IndexedStrategy>);
}

impl IndexedStrategyImpl of IndexedStrategyTrait {
    fn assert_no_duplicate_indices(self: @Array<IndexedStrategy>) {
        if self.len() < 2 {
            return ();
        }

        let mut bit_map = 0_u256;
        let mut i = 0_usize;
        loop {
            if i >= self.len() {
                break ();
            }
            // Check that bit at index `strats[i].index` is not set.
            let s = math::pow(2_u256, *self.at(i).index);

            assert((bit_map & s) == 1_u256, 'Duplicate Found');
            // Update aforementioned bit.
            bit_map = bit_map | s;
            i += 1;
        };
    }
}

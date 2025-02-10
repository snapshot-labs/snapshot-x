use starknet::{ContractAddress, EthAddress};
use sx::utils::ContractAddressDefault;

/// Enum to represent a user address.
#[derive(Copy, Default, Drop, Serde, PartialEq, starknet::Store)]
enum UserAddress {
    /// Starknet address type
    #[default]
    Starknet: ContractAddress,
    /// Ethereum address type
    Ethereum: EthAddress,
    /// Custom address type to provide compatibility with any address that can be represented as a u256.
    Custom: u256
}

trait UserAddressTrait {
    fn to_starknet_address(self: UserAddress) -> ContractAddress;
    fn to_ethereum_address(self: UserAddress) -> EthAddress;
    fn to_custom_address(self: UserAddress) -> u256;
}

impl UserAddressImpl of UserAddressTrait {
    /// Returns the starknet address. Panics if the address is not a starknet address.
    fn to_starknet_address(self: UserAddress) -> ContractAddress {
        match self {
            UserAddress::Starknet(address) => address,
            UserAddress::Ethereum(_) => { panic_with_felt252('Incorrect address type') },
            UserAddress::Custom(_) => { panic_with_felt252('Incorrect address type') }
        }
    }

    /// Returns the ethereum address. Panics if the address is not an ethereum address.
    fn to_ethereum_address(self: UserAddress) -> EthAddress {
        match self {
            UserAddress::Starknet(_) => { panic_with_felt252('Incorrect address type') },
            UserAddress::Ethereum(address) => address,
            UserAddress::Custom(_) => { panic_with_felt252('Incorrect address type') }
        }
    }

    /// Returns the custom address. Panics if the address is not a custom address.
    fn to_custom_address(self: UserAddress) -> u256 {
        match self {
            UserAddress::Starknet(_) => { panic_with_felt252('Incorrect address type') },
            UserAddress::Ethereum(_) => { panic_with_felt252('Incorrect address type') },
            UserAddress::Custom(address) => address,
        }
    }
}

impl UserAddressZeroable of Zeroable<UserAddress> {
    fn zero() -> UserAddress {
        panic_with_felt252('Undefined')
    }

    fn is_zero(self: UserAddress) -> bool {
        match self {
            UserAddress::Starknet(address) => address.is_zero(),
            UserAddress::Ethereum(address) => address.is_zero(),
            UserAddress::Custom(address) => address.is_zero(),
        }
    }

    fn is_non_zero(self: UserAddress) -> bool {
        !self.is_zero()
    }
}

#[cfg(test)]
mod tests {
    use super::{UserAddress, UserAddressZeroable};
    use starknet::{EthAddress, contract_address_const};

    #[test]
    fn is_zero() {
        assert(UserAddress::Starknet(contract_address_const::<0>()).is_zero(), 'is not zero');
        assert(UserAddress::Ethereum(EthAddress { address: 0 }).is_zero(), 'is not zero');
        assert(UserAddress::Custom(0_u256).is_zero(), 'is not zero');
    }

    #[test]
    fn is_zero_false_positive() {
        assert(
            UserAddress::Starknet(contract_address_const::<1>()).is_zero() == false,
            'false positive not zero'
        );
        assert(
            UserAddress::Ethereum(EthAddress { address: 1 }).is_zero() == false,
            'false positive not zero'
        );
        assert(UserAddress::Custom(1_u256).is_zero() == false, 'false positive not zero');
    }

    #[test]
    fn is_non_zero() {
        assert(UserAddress::Starknet(contract_address_const::<1>()).is_non_zero(), 'is zero');
        assert(UserAddress::Ethereum(EthAddress { address: 1 }).is_non_zero(), 'is zero');
        assert(UserAddress::Custom(1_u256).is_non_zero(), 'is zero');
    }

    #[test]
    fn is_non_zero_false_positive() {
        assert(
            UserAddress::Starknet(contract_address_const::<0>()).is_non_zero() == false,
            'false positive is zero'
        );
        assert(
            UserAddress::Ethereum(EthAddress { address: 0 }).is_non_zero() == false,
            'false positive is zero'
        );
        assert(UserAddress::Custom(0_u256).is_non_zero() == false, 'false positive not zero');
    }
}

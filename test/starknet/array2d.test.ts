import { StarknetContract } from 'hardhat/types/runtime';
import { expect } from 'chai';
import { starknet } from 'hardhat';
import { utils } from '@snapshot-labs/sx';

async function setup() {
  const testArray2dFactory = await starknet.getContractFactory(
    './contracts/starknet/TestContracts/Test_array2d.cairo'
  );
  const testArray2d = await testArray2dFactory.deploy();
  return {
    testArray2d: testArray2d as StarknetContract,
  };
}

describe('2D Arrays:', () => {
  it('The library should be able to construct the 2D array type from a flat array and then retrieve the sub arrays individually.', async () => {
    const { testArray2d } = await setup();

    // Sub Arrays: [[5],[],[1,2,3],[7,9]]
    // Offsets: [0,1,1,4]
    const arr1: bigint[] = [BigInt(5)];
    const arr2: bigint[] = [];
    const arr3: bigint[] = [BigInt(1), BigInt(2), BigInt(3)];
    const arr4: bigint[] = [BigInt(7), BigInt(9)];
    const arr2d: bigint[][] = [arr1, arr2, arr3, arr4];
    const flatArray: bigint[] = utils.encoding.flatten2DArray(arr2d);

    const { array: array1 } = await testArray2d.call('test_array2d', {
      flat_array: flatArray,
      index: 0,
    });
    expect(array1).to.deep.equal(arr1);

    const { array: array2 } = await testArray2d.call('test_array2d', {
      flat_array: flatArray,
      index: 1,
    });
    expect(array2).to.deep.equal(arr2);

    const { array: array3 } = await testArray2d.call('test_array2d', {
      flat_array: flatArray,
      index: 2,
    });
    expect(array3).to.deep.equal(arr3);

    const { array: array4 } = await testArray2d.call('test_array2d', {
      flat_array: flatArray,
      index: 3,
    });
    expect(array4).to.deep.equal(arr4);

    // Sub Arrays: [[]]
    // Offsets: [0]
    const arr2d2 = [arr2];
    const flatArray2 = utils.encoding.flatten2DArray(arr2d2);
    const { array: array5 } = await testArray2d.call('test_array2d', {
      flat_array: flatArray2,
      index: 0,
    });
    expect(array5).to.deep.equal(arr2);
  }).timeout(600000);
});

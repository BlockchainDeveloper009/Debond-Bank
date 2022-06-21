import {
    APMInstance,
    BankInstance,
    DBITTestInstance,
    DebondBondTestInstance,
    USDCInstance,
    USDTInstance
} from "../types/truffle-contracts";

const Bank = artifacts.require("Bank");
const USDC = artifacts.require("USDC");
const USDT = artifacts.require("USDT");
const DBIT = artifacts.require("DBITTest");
const APM = artifacts.require("APMTest");
const DebondBondTest = artifacts.require("DebondBondTest");



contract('Bank', async (accounts: string[]) => {
    const buyer = accounts[1];
    enum PurchaseMethod {
        BUYING = 0,
        STAKING = 1,
    }

    let usdcContract: USDCInstance
    let usdtContract: USDTInstance
    let bankContract: BankInstance
    let dbitContract: DBITTestInstance
    let apmContract: APMInstance
    let bondContract: DebondBondTestInstance

    const DBIT_FIX_6MTH_CLASS_ID = 0;
    const USDC_FIX_6MTH_CLASS_ID = 1;
    const USDT_FIX_6MTH_CLASS_ID = 2;

    it('buy Bonds with USDC', async () => {
        usdcContract = await USDC.deployed();
        usdtContract = await USDT.deployed();
        bankContract = await Bank.deployed();
        dbitContract = await DBIT.deployed();
        apmContract = await APM.deployed();
        bondContract = await DebondBondTest.deployed();


        await usdcContract.mint(buyer, web3.utils.toWei('100000', 'ether'));
        await usdcContract.approve(bankContract.address, web3.utils.toWei('100000', 'ether'), {from: buyer});
        await bankContract.buyBond(USDC_FIX_6MTH_CLASS_ID, DBIT_FIX_6MTH_CLASS_ID, web3.utils.toWei('3000', 'ether'), 0, PurchaseMethod.BUYING,0, {from: buyer});
        const DBITNonces = (await bondContract.getNoncesPerAddress(buyer, DBIT_FIX_6MTH_CLASS_ID)).map(n => n.toNumber());
        console.log("balance Bond D/BIT: AFTER " + (await bondContract.balanceOf(buyer, DBIT_FIX_6MTH_CLASS_ID, DBITNonces[0])));



    })

    it('buy Bonds with USDT', async () => {

        usdcContract = await USDC.deployed();
        usdtContract = await USDT.deployed();
        bankContract = await Bank.deployed();
        dbitContract = await DBIT.deployed();
        apmContract = await APM.deployed();
        bondContract = await DebondBondTest.deployed();

        await usdtContract.mint(buyer, web3.utils.toWei('100000', 'ether'));
        await usdtContract.approve(bankContract.address, web3.utils.toWei('100000', 'ether'), {from: buyer});
        await bankContract.buyBond(USDT_FIX_6MTH_CLASS_ID, DBIT_FIX_6MTH_CLASS_ID, web3.utils.toWei('3000', 'ether'), 0, PurchaseMethod.BUYING,0, {from: buyer});
        const DBITNonces = (await bondContract.getNoncesPerAddress(buyer, DBIT_FIX_6MTH_CLASS_ID)).map(n => n.toNumber());
        console.log("balance Bond D/BIT: AFTER " + (await bondContract.balanceOf(buyer, DBIT_FIX_6MTH_CLASS_ID, DBITNonces[0])));



    })

    it('redeem Bonds', async () => {

        const DBITNonces = (await bondContract.getNoncesPerAddress(buyer, DBIT_FIX_6MTH_CLASS_ID)).map(n => n.toNumber());
        console.log("nonce: " + DBITNonces[0]);
        await bankContract.redeemBonds(DBIT_FIX_6MTH_CLASS_ID, DBITNonces[0], web3.utils.toWei('1000', 'ether'), {from: buyer});

        console.log("balance Bond D/BIT: AFTER " + (await bondContract.balanceOf(buyer, DBIT_FIX_6MTH_CLASS_ID, DBITNonces[0])));
    })
});

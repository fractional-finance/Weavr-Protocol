const { ethers, upgrades } = require("hardhat");
const { assert, expect } = require("chai");

// const { proposal, propose } = require("../common.js");
const {FRABRIC, proposalUtils} = require("../VTP_modular");


const WALLETS = (process.env.WALLETS).split(",");

const utils = proposalUtils ;
const isAddress = ethers.utils.isAddress;

const DEX = {
    utils: {
        buy: async( dex, frbcAddress, usdAddress, buyer, tokenAmount, tokenPrice ) => {
            try {
                // await usd.approve(dex.address, ethers.constants.MaxUint256, {
                //     gasLimit: 300000
                // });
                dex.connect(buyer);
                const nToken = tokenAmount || 10;
                const pToken = tokenPrice || 5;
                const amount = pToken * nToken;
                const tx = await dex.buy(
                    frbcAddress, 
                    usdAddress, 
                    amount, 
                    pToken, 
                    nToken
                );
                console.log("BUY_TX_HASH: ", tx.hash);   
                return (true);
            } catch (error) {
                console.log(error);
                return (false);
            }
        },
        sell: async( frbc, seller, tokenAmount, tokenPrice ) => {
            
            frbc.connect(seller);
            const price = tokenPrice || 5;
            const nToken = tokenAmount || 10;
            try {
                const tx = await frbc.sell(
                    ethers.BigNumber.from(price),
                    ethers.BigNumber.from(nToken)
                ) 
                console.log("SELL_TX_HASH: ", tx.hash);   
            } catch (error) {
                console.log(error)
            }
        }
    }
}

module.exports = async () => {

    const provider = new ethers.providers.AlchemyProvider(config.network ? config.network : 5);
    const signers = utils.walletSetup(provider, WALLETS);

    const seller = signers[1];
    const buyer = signers[0];
    console.log(ethers.utils.isAddress(seller.address));

    const frabric = await new ethers.Contract(
        process.env.INITIALFRABRIC,
        require('../../../artifacts/contracts/frabric/Frabric.sol/Frabric.json').abi,
        seller
    )
    
    const frbc = await new ethers.Contract(
        process.env.FRBC,
        require('../../../artifacts/contracts/erc20/FrabricERC20.sol/FrabricERC20.json').abi,
        seller
    )

    const dex = await new ethers.Contract(
        process.env.DEXROUTER,
        require('../../../artifacts/contracts/erc20/DEXRouter.sol/DEXRouter.json').abi,
        buyer
    )

     // Get simple ERC20 token ABI
     const usd = new ethers.Contract(process.env.USD,
        require("../../../artifacts/contracts/test/TestERC20.sol/TestERC20.json").abi,
        buyer
    )

    if(isAddress(frbc.address)){
        console.log(dex.address);
        
        /**
         *  { SELL }
         */
        await DEX.utils.sell(frbc, seller, 1, 1);
        // const price = 10
        // const nToken = 12
        // try {
        //     const tx = await frbc.sell(
        //         ethers.BigNumber.from(price),
        //         ethers.BigNumber.from(nToken)
        //     ) 
        //     console.log("SELL_TX_HASH: ", tx.hash);   
        // } catch (error) {
        //     console.log(error);
        // }
        
        /**
         *  { BUY }
         */
        await DEX.utils.buy(dex, frbc.address, usd.address, buyer, 12, 1);
        // try {
        //     // Get simple ERC20 token ABI
        //     const usd = new ethers.Contract(process.env.USD,
        //         require("../../../artifacts/contracts/test/TestERC20.sol/TestERC20.json").abi,
        //         buyer
        //     )
        //     // await usd.approve(dex.address, ethers.constants.MaxUint256, {
        //     //     gasLimit: 300000
        //     // });
        //     const nToken = 10
        //     const pToken = 5
        //     const amount = pToken * nToken
        //     const tx = await dex.buy(
        //         process.env.FRBC, 
        //         process.env.USD, 
        //         amount, 
        //         pToken, 
        //         nToken
        //     );
        //     console.log("BUY_TX_HASH: ", tx.hash);   
        // } catch (error) {
        //     console.log(error)
        // }

        /**
         *  { GET_ORDERS }
         */
        /***
         * ORDERS
         */
         const order = await (await frbc.queryFilter(frbc.filters.Order()))
         console.log("------------  ORDERS -------------")
         order.map( ( order ) => {
            console.log(order.args);
         })

        /***
         * INCREASED ORDER
         */
        const orderIncrease = await (await frbc.queryFilter(frbc.filters.OrderIncrease()))
        console.log("------------  INCREASE -------------")
        orderIncrease.map( ( order ) => {
            console.log(order.args);
         })

        /***
         * FILLED ORDERS
         */
         const orderFill = await (await frbc.queryFilter(frbc.filters.OrderFill()))
         console.log("------------  FILL -------------")
         orderIncrease.map( ( order ) => {
            console.log(order.args);
         })

         /***
         * CANCELLING ORDERS
         */
         const orderCancelling = await (await frbc.queryFilter(frbc.filters.OrderCancelling()))
         console.log("------------  CANCELLING -------------")
         orderCancelling.map( ( order ) => {
            console.log(order.args);
         })

        /***
         * CANCELLATION ORDERS
         */
         const orderCancellation = await (await frbc.queryFilter(frbc.filters.OrderCancellation()))
         console.log("------------  CANCELLED -------------")
         orderCancellation.map( ( order ) => {
            console.log(order.args);
         })
        
    }
    
    
}

const callModule = async () => {
    console.log("YESS");
    await module.exports()
}

if (require.main === module) {
    callModule()
}

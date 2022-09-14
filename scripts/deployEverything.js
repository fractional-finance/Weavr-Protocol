const hre = require("hardhat");
const { ethers, upgrades, waffle  } = hre;
const { expect } = require("chai");

const deployInitialFrabric = require("./deployInitialFrabric.js");
const deployFrabric = require("./deployFrabric.js");

const genesis = require("../genesis.json");

(async () => {
    console.log("AAAA");
    let config = {
        USD: process.env.USD,
        UNISWAP: process.env.UNISWAP
    }

    console.log("CONFIG:\t\t", config);

    let initialFrabric = await deployInitialFrabric(config.USD, config.UNISWAP, genesis, 240, 10, 36000).then( x => {
        console.log("Initial Frabric Deployed");
        console.log(x);
        return x
    });

    let {
        auction,
        erc20Beacon,
        frbc,
        pair,
        beacon,
        frabric,
        router
    } = initialFrabric;

    console.log({
        AUCTION: initialFrabric.auction.address,
        ERC20_BEACON: initialFrabric.erc20Beacon.address,
        FRBC: initialFrabric.frbc.address,
        FRBC_USD_PAIR: initialFrabric.pair,
        SINGLEBEACON: initialFrabric.beacon.address,
        FRABRIC: initialFrabric.frabric.address,
        ROUTER: initialFrabric.router.address
    });

    const isAddress = ethers.utils.isAddress
    while(
        !isAddress(initialFrabric.auction.address) ||
        !isAddress(initialFrabric.erc20Beacon.address) ||
        !isAddress(initialFrabric.pair) ||
        !isAddress(initialFrabric.frabric.address)
    ){
        console.log("Contracts not ready!!");
        setTimeout(
            () => {

            },1000
        )
    }



    console.log("Deploying Frabric");
    frabric = await deployFrabric(auction.address, erc20Beacon.address, config.USD, pair, frabric.address);

    console.log("AUCTION=" + initialFrabric.auction.address);
    console.log("ERC20BEACON=" + initialFrabric.erc20Beacon.address);
    console.log("FRBC=" + initialFrabric.frbc.address);
    console.log("PAIR=" + initialFrabric.pair);
    console.log("PROXY=" + initialFrabric.beacon.address);
    console.log("INITIALFRABRIC=" + initialFrabric.frabric.address);
    console.log("DEXROUTER=" + initialFrabric.router.address);
    
    console.log("Thread Deployer=" + frabric.threadDeployer.address);
    console.log("Bond=" + frabric.bond.address);
    console.log("Frabric Code=" + frabric.frabricCode);
})

(async () => {
   console.log("SECOND");

    let config = {
        USD: process.env.USD,
        UNISWAP: process.env.UNISWAP
    }

    
    // (config.UNISWAP == "") ? process.env.UNISWAP : config.UNISWAP
    // (config.USD == "") ? process.env.USD : config.USD

    console.log("CONFIG:\\t\\t", config);

})

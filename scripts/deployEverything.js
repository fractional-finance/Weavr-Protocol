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

    let initialFrabric = await deployInitialFrabric(config.USD, config.UNISWAP, genesis);

    let {
        auction,
        erc20Beacon,
        frbc,
        pair,
        proxy,
        frabric,
        router
    } = initialFrabric;

    console.log({
        AUCTION: auction.address,
        ERC20_BEACON: erc20Beacon.address,
        FRBC: frbc.address,
        FRBC_USD_PAIR: pair,
        PROXY: proxy.address,
        FRABRIC: frabric.address,
        ROUTER: router.address
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

    console.log("AUCTION:           " + initialFrabric.auction.address);
    console.log("ERC20BEACON:       " + initialFrabric.erc20Beacon.address);
    console.log("FRBC:              " + initialFrabric.frbc.address);
    console.log("PAIR:              " + initialFrabric.pair);
    console.log("PROXY:             " + initialFrabric.proxy.address);
    console.log("INITIALFRABRIC:    " + initialFrabric.frabric.address);
    console.log("DEXROUTER:         " + initialFrabric.router.address);
    
    console.log("Thread Deployer:   " + frabric.threadDeployer.address);
    console.log("Bond:              " + frabric.bond.address);
    console.log("Frabric Code:      " + frabric.frabricCode);
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

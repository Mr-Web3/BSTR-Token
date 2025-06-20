// deploy/BSTRToken.ts
import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import { parseUnits } from "ethers/lib/utils";

const deployBSTR: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployer } = await hre.getNamedAccounts();
  const { deploy, get, log } = hre.deployments;

  const initialSupply = parseUnits("1000000", 9); // 1000000 BSTR
  // const feeReceiver = "0x02E0D53DC55F219B3B149F2FbD164Da0e5f936F8"; // Fee receiver address Main net Real Address
  // const swapRouter = "0xYourUniswapRouterAddress"; // <- replace with real router Main net Real Address
  // const collectors = ["0xc402DCe90308bD61eb492B1146BE0236DCcD7e13"]; // Collectors address Main net Real Address

  const feeReceiver = deployer; // Fee receiver address
  const swapRouter = "0x1689E7B1F10000AE47eBfE339a4f69dECd19F602"; // <- replace with real router This is test net router
  const collectors = ["0xBe94738C517E3f71475EF68AD62215c38949cA58"]; // Collectors address replace with real address
  const shares = [100]; // 100% to collectors address

  log("🚀 Deploying BSTRToken...");
  const bstrToken = await deploy("BSTRToken", {
    from: deployer,
    args: [
      initialSupply,
      feeReceiver,
      swapRouter,
      collectors,
      shares
    ],
    log: true,
    autoMine: true,
    value: "100000000000000000", // 0.1 ETH in wei
  });

  const createClickableLinkBSTRToken = (address: string, label: string) => {
    const baseUrl = "https://sepolia.basescan.org/address/";
    return `\x1b]8;;${baseUrl}${address}\x07${label}\x1b]8;;\x07`;
  };

  
  // Governance Contract Deployment That will be used for the governance of the BSTRToken later after the token is deployed & REX is ready for the governance DAO.

  // const IVotes = "0x0000000000000000000000000000000000000000"; // This is the address of the IVotes contract
  // const TimelockController = "0x0000000000000000000000000000000000000000"; // This is the address of the timelock contract
  // const votingDelay = 1;
  // const votingPeriod = 100;
  // const proposalThreshold = 1;
  // const quorumPercentage = 1;

  // const GovernorBSTR = await deploy("GovernorBSTR", {
  //   from: deployer,
  //   args: [IVotes, TimelockController, votingDelay, votingPeriod, proposalThreshold, quorumPercentage],
  //   log: true,
  //   autoMine: true,
  // });

  // const createClickableLinkGovernorBSTR = (address: string, label: string) => {
  //   const baseUrl = "https://sepolia.basescan.org/address/";
  //   return `\x1b]8;;${baseUrl}${address}\x07${label}\x1b]8;;\x07`;
  // };

  console.log("\n=== 📝 Deployment Summary ===");
  console.log(`🪙 BSTRToken: ${createClickableLinkBSTRToken(bstrToken.address, bstrToken.address)}`);
  // console.log(`🗳️ gBSTR Governance Wrapper: ${createClickableLinkGovernorBSTR(GovernorBSTR.address, GovernorBSTR.address)}`);
};

export default deployBSTR;
deployBSTR.tags = ["BSTRToken"];

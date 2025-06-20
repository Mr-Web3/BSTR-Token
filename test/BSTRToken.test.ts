import { ethers } from "hardhat";
import { expect } from "chai";
import { BSTRToken } from "../typechain-types";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";

describe("BSTRToken", () => {
  let bstr: BSTRToken;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;
  let swapRouter: string;
  let collectors: string[];
  let shares: number[];
  const initialSupply = ethers.parseUnits("1000000", 9);

  beforeEach(async function() {
    // Get signers
    const signers = await ethers.getSigners();
    owner = signers[0];
    addr1 = signers[1];
    addr2 = signers[2];

    // Deploy contract
    swapRouter = "0x1689E7B1F10000AE47eBfE339a4f69dECd19F602";
    collectors = [owner.address];
    shares = [100];

    const BSTR = await ethers.getContractFactory("BSTRToken");
    bstr = await BSTR.deploy(
      initialSupply,
      owner.address,
      swapRouter,
      collectors,
      shares,
      { value: ethers.parseEther("0.1") }
    ) as BSTRToken;

    await bstr.waitForDeployment();
  });

  describe("Initialization", () => {
    it("should have correct initial supply", async () => {
      const totalSupply = await bstr.totalSupply();
      expect(totalSupply).to.equal(initialSupply);
      expect(await bstr.balanceOf(owner.address)).to.equal(initialSupply);
    });

    it("should have correct name and symbol", async () => {
      expect(await bstr.name()).to.equal("Buster");
      expect(await bstr.symbol()).to.equal("BSTR");
      expect(await bstr.decimals()).to.equal(9);
    });

    it("should have correct initial fee configuration", async () => {
      const config = await bstr.feeConfiguration();
      expect(config.buyFees).to.equal(500);
      expect(config.sellFees).to.equal(500);
      expect(config.transferFees).to.equal(0);
      expect(config.burnFeeRatio).to.equal(0);
      expect(config.liquidityFeeRatio).to.equal(5000);
      expect(config.collectorsFeeRatio).to.equal(5000);
    });
  });

  describe("Fee Management", () => {
    it("should allow owner to update tax rates", async () => {
      await bstr.setTaxRates(300, 400);
      const config = await bstr.feeConfiguration();
      expect(config.buyFees).to.equal(300);
      expect(config.sellFees).to.equal(400);
    });

    it("should not allow non-owner to update tax rates", async () => {
      const bstrAsAddr1 = bstr.connect(addr1) as BSTRToken;
      await expect(bstrAsAddr1.setTaxRates(300, 400))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should not allow tax rates above MAX_FEE", async () => {
      await expect(bstr.setTaxRates(10001, 500))
        .to.be.revertedWith("Tax too high");
    });
  });

  describe("Fee Collectors", () => {
    it("should allow owner to add fee collector", async () => {
      await bstr.addFeeCollector(addr1.address, 50);
      expect(await bstr.isFeeCollector(addr1.address)).to.be.true;
    });

    it("should allow owner to remove fee collector", async () => {
      await bstr.addFeeCollector(addr1.address, 50);
      await bstr.removeFeeCollector(addr1.address);
      expect(await bstr.isFeeCollector(addr1.address)).to.be.false;
    });

    it("should allow owner to update collector share", async () => {
      await bstr.addFeeCollector(addr1.address, 50);
      await bstr.updateFeeCollectorShare(addr1.address, 75);
    });
  });

  describe("Access Control", () => {
    it("should only allow owner to set autoprocess fees", async () => {
      const bstrAsAddr1 = bstr.connect(addr1) as BSTRToken;
      await expect(bstrAsAddr1.setAutoprocessFees(true))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should only allow owner to set liquidity owner", async () => {
      const bstrAsAddr1 = bstr.connect(addr1) as BSTRToken;
      await expect(bstrAsAddr1.setLiquidityOwner(addr2.address))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("should only allow owner to set swap router", async () => {
      const bstrAsAddr1 = bstr.connect(addr1) as BSTRToken;
      await expect(bstrAsAddr1.setSwapRouter(addr2.address))
        .to.be.revertedWith("Ownable: caller is not the owner");
    });
  });

  describe("Token Transfers", () => {
    it("should transfer tokens without fees when excluded", async () => {
      const amount = ethers.parseUnits("1000", 9);
      await bstr.setIsExcludedFromFees(addr1.address, true);
      await bstr.transfer(addr1.address, amount);
      expect(await bstr.balanceOf(addr1.address)).to.equal(amount);
    });

    it("should apply fees on regular transfers", async () => {
      const amount = ethers.parseUnits("1000", 9);
      await bstr.transfer(addr1.address, amount);
      const balance = await bstr.balanceOf(addr1.address);
      expect(balance).to.be.below(amount);
    });
  });

  describe("Fee Processing", () => {
    it("should allow owner to process fees", async () => {
      const amount = ethers.parseUnits("1000", 9);
      await bstr.transfer(addr1.address, amount);
      
      const contractBalance = await bstr.balanceOf(await bstr.getAddress());
      if (contractBalance > 0n) {
        await bstr.processFees(contractBalance, 0);
      }
    });

    it("should allow owner to distribute fees", async () => {
      const amount = ethers.parseUnits("1000", 9);
      await bstr.transfer(addr1.address, amount);
      
      const contractBalance = await bstr.balanceOf(await bstr.getAddress());
      if (contractBalance > 0n) {
        await bstr.distributeFees(contractBalance, true);
      }
    });
  });
});

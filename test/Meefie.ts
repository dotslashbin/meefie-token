import { expect } from 'chai'
import { ethers } from 'hardhat'
import { ethers as ethersFromEthers } from 'ethers'

describe('MeeFie Token', () => {
	let owner: any

	let MeeFieToken: any
	let tokenToDeploy: any

	const initialSupplyWallet = '0x8d7449acf6d894d05f21bdc051737564991d83a8'
	const initialTaxWallet = '0xf0004aC825ccdf756dBA8dE2500A06d4B12C8FB0'

	beforeEach(async function () {
		;[owner] = await ethers.getSigners()

		tokenToDeploy = await ethers.getContractFactory('MeeFieToken')
		MeeFieToken = await tokenToDeploy.deploy(initialSupplyWallet)
	})

	describe('Token contract', () => {
		it('Deployment should assign the supply to the inidcated initial supply wallet', async () => {
			const supplyWalletBalance = await MeeFieToken.balanceOf(
				initialSupplyWallet
			)
			expect(await MeeFieToken.totalSupply()).to.equal(supplyWalletBalance)
		})

		it('Token should be able to update the tax wallet', async () => {
			await MeeFieToken.connect(owner).updateTaxWallet(initialTaxWallet)
		})
	})
})

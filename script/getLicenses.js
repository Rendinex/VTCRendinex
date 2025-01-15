require("dotenv").config();
const { ethers } = require("ethers");
const abi = require("../out/VTCContract.sol/RVTC.json");

const providerUrl = process.env.SEPOLIA_RPC_URL;
console.log("Provider URL:", providerUrl);

// Create an ethers provider (e.g., Infura, Alchemy, or a local provider)
const provider = new ethers.JsonRpcProvider(providerUrl);
console.log(provider);

// The contract address
const contractAddress = "0xdE62bd2Aba018c8e4EE2F8f81c117fE56b9B3A83";

// Initialize the contract with the provider and contract ABI
const contract = new ethers.Contract(contractAddress, abi.abi, provider);

async function getLicenses() {
    try {
        // Call the getLicenses function from the contract
        const result = await contract.getLicenses();

        // Log the raw result to debug
        console.log("Raw License Data:", result);

        // Ensure the result is in the expected format
        if (result && result.length >= 4) {
            const ids = result[0]; // Array of license IDs
            const fundingGoals = result[1]; // Array of funding goals
            const fundsRaised = result[2]; // Array of funds raised
            const fundingCompleted = result[3]; // Array of completion statuses

            // Display the results
            console.log("Licenses Information:");
            for (let i = 0; i < ids.length; i++) {
                console.log(`License ID: ${ids[i]}`);
                console.log(`Raw Funding Goal: ${fundingGoals[i]}`);
                console.log(`Raw Funds Raised: ${fundsRaised[i]}`);
                console.log(`Funding Completed: ${fundingCompleted[i]}`);
            }
        } else {
            console.error("Unexpected result format:", result);
        }
    } catch (error) {
        console.error("Error fetching licenses:", error);
    }
}

getLicenses();

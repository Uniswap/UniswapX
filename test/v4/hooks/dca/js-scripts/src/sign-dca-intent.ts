#!/usr/bin/env node
import {
  privateKeyToAccount,
} from 'viem/accounts'
import {
  createWalletClient,
  http,
  type Address,
  toHex,
  pad,
  keccak256,
  encodeAbiParameters,
} from 'viem'

// Read command line arguments
const args = process.argv.slice(2);
if (args.length < 1) {
  console.error("Usage: sign-dca-intent <jsonInput>");
  process.exit(1);
}

// Parse the JSON input
interface FeedTemplate {
  name: string;
  expression: string;
  parameters: string[];
  secrets: string[];
  retryCount: number;
}

interface FeedInfo {
  feedTemplate: FeedTemplate;
  feedAddress: Address;
  feedType: string;
}

interface OutputAllocation {
  recipient: Address;
  basisPoints: number;
}

interface PrivateIntent {
  totalAmount: bigint;
  exactFrequency: bigint;
  numChunks: bigint;
  salt: `0x${string}`;
  oracleFeeds: FeedInfo[];
}

interface DCAIntent {
  swapper: Address;
  nonce: bigint;
  chainId: bigint;
  hookAddress: Address;
  isExactIn: boolean;
  inputToken: Address;
  outputToken: Address;
  cosigner: Address;
  minPeriod: bigint;
  maxPeriod: bigint;
  minChunkSize: bigint;
  maxChunkSize: bigint;
  minPrice: bigint;
  deadline: bigint;
  outputAllocations: OutputAllocation[];
  privateIntent: PrivateIntent;
}

interface SignDCAIntentInput {
  privateKey: string;
  verifyingContract: Address;
  chainId: number;
  intent: DCAIntent;
}

// Define the EIP-712 types
const DCAIntentTypes = {
  DCAIntent: [
    { name: 'swapper', type: 'address' },
    { name: 'nonce', type: 'uint256' },
    { name: 'chainId', type: 'uint256' },
    { name: 'hookAddress', type: 'address' },
    { name: 'isExactIn', type: 'bool' },
    { name: 'inputToken', type: 'address' },
    { name: 'outputToken', type: 'address' },
    { name: 'cosigner', type: 'address' },
    { name: 'minPeriod', type: 'uint256' },
    { name: 'maxPeriod', type: 'uint256' },
    { name: 'minChunkSize', type: 'uint256' },
    { name: 'maxChunkSize', type: 'uint256' },
    { name: 'minPrice', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
    { name: 'outputAllocations', type: 'OutputAllocation[]' },
    { name: 'privateIntent', type: 'PrivateIntent' },
  ],
  OutputAllocation: [
    { name: 'recipient', type: 'address' },
    { name: 'basisPoints', type: 'uint16' },
  ],
  PrivateIntent: [
    { name: 'totalAmount', type: 'uint256' },
    { name: 'exactFrequency', type: 'uint256' },
    { name: 'numChunks', type: 'uint256' },
    { name: 'salt', type: 'bytes32' },
    { name: 'oracleFeeds', type: 'FeedInfo[]' },
  ],
  FeedInfo: [
    { name: 'feedTemplate', type: 'FeedTemplate' },
    { name: 'feedAddress', type: 'address' },
    { name: 'feedType', type: 'string' },
  ],
  FeedTemplate: [
    { name: 'name', type: 'string' },
    { name: 'expression', type: 'string' },
    { name: 'parameters', type: 'string[]' },
    { name: 'secrets', type: 'string[]' },
    { name: 'retryCount', type: 'uint256' },
  ],
} as const;

const jsonInput = JSON.parse(args[0]) as SignDCAIntentInput;
const { privateKey, verifyingContract, chainId, intent } = jsonInput;

const account = privateKeyToAccount(pad(toHex(BigInt(privateKey))));

const walletClient = createWalletClient({
  account,
  transport: http('http://127.0.0.1:8545')
})

async function signDCAIntent(): Promise<void> {
  try {
    const domain = {
      name: 'DCAHook',
      version: '1',
      chainId: chainId,
      verifyingContract: verifyingContract,
    }

    const signature = await walletClient.signTypedData({
      account,
      domain,
      types: DCAIntentTypes,
      primaryType: 'DCAIntent',
      message: intent,
    })

    // Also compute and return the hash for verification
    const structHash = keccak256(
      encodeAbiParameters(
        [
          { type: 'bytes32' }, // typehash
          { type: 'address' }, // swapper
          { type: 'uint256' }, // nonce
          { type: 'uint256' }, // chainId
          { type: 'address' }, // hookAddress
          { type: 'bool' },    // isExactIn
          { type: 'address' }, // inputToken
          { type: 'address' }, // outputToken
          { type: 'address' }, // cosigner
          { type: 'uint256' }, // minPeriod
          { type: 'uint256' }, // maxPeriod
          { type: 'uint256' }, // minChunkSize
          { type: 'uint256' }, // maxChunkSize
          { type: 'uint256' }, // minPrice
          { type: 'uint256' }, // deadline
          { type: 'bytes32' }, // outputAllocations hash
          { type: 'bytes32' }, // privateIntent hash
        ],
        [
          keccak256(toHex('DCAIntent(address swapper,uint256 nonce,uint256 chainId,address hookAddress,bool isExactIn,address inputToken,address outputToken,address cosigner,uint256 minPeriod,uint256 maxPeriod,uint256 minChunkSize,uint256 maxChunkSize,uint256 minPrice,uint256 deadline,OutputAllocation[] outputAllocations,PrivateIntent privateIntent)FeedInfo(FeedTemplate feedTemplate,address feedAddress,string feedType)FeedTemplate(string name,string expression,string[] parameters,string[] secrets,uint256 retryCount)OutputAllocation(address recipient,uint16 basisPoints)PrivateIntent(uint256 totalAmount,uint256 exactFrequency,uint256 numChunks,bytes32 salt,FeedInfo[] oracleFeeds)')),
          intent.swapper,
          intent.nonce,
          intent.chainId,
          intent.hookAddress,
          intent.isExactIn,
          intent.inputToken,
          intent.outputToken,
          intent.cosigner,
          intent.minPeriod,
          intent.maxPeriod,
          intent.minChunkSize,
          intent.maxChunkSize,
          intent.minPrice,
          intent.deadline,
          hashOutputAllocations(intent.outputAllocations),
          hashPrivateIntent(intent.privateIntent),
        ]
      )
    );

    // Return both signature and hash as JSON
    const result = JSON.stringify({
      signature,
      structHash,
    });

    process.stdout.write(result);
    process.exit(0);
  } catch (error) {
    console.error('Error signing DCA intent:', error);
    process.exit(1);
  }
}

function hashOutputAllocations(allocations: OutputAllocation[]): `0x${string}` {
  const hashes = allocations.map(alloc =>
    keccak256(
      encodeAbiParameters(
        [
          { type: 'bytes32' },
          { type: 'address' },
          { type: 'uint16' },
        ],
        [
          keccak256(toHex('OutputAllocation(address recipient,uint16 basisPoints)')),
          alloc.recipient,
          alloc.basisPoints,
        ]
      )
    )
  );

  return keccak256(encodeAbiParameters(
    hashes.map(() => ({ type: 'bytes32' })),
    hashes
  ));
}

function hashStringArray(arr: string[]): `0x${string}` {
  const hashes = arr.map(str => keccak256(toHex(str)));
  return keccak256(encodeAbiParameters(
    hashes.map(() => ({ type: 'bytes32' })),
    hashes
  ));
}

function hashFeedTemplate(template: FeedTemplate): `0x${string}` {
  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'bytes32' },
        { type: 'uint256' },
      ],
      [
        keccak256(toHex('FeedTemplate(string name,string expression,string[] parameters,string[] secrets,uint256 retryCount)')),
        keccak256(toHex(template.name)),
        keccak256(toHex(template.expression)),
        hashStringArray(template.parameters),
        hashStringArray(template.secrets),
        BigInt(template.retryCount),
      ]
    )
  );
}

function hashPrivateIntent(privateIntent: PrivateIntent): `0x${string}` {
  const feedHashes = privateIntent.oracleFeeds.map(feed => {
    const templateHash = hashFeedTemplate(feed.feedTemplate);
    return keccak256(
      encodeAbiParameters(
        [
          { type: 'bytes32' },
          { type: 'bytes32' },
          { type: 'address' },
          { type: 'bytes32' },
        ],
        [
          keccak256(toHex('FeedInfo(FeedTemplate feedTemplate,address feedAddress,string feedType)FeedTemplate(string name,string expression,string[] parameters,string[] secrets,uint256 retryCount)')),
          templateHash,
          feed.feedAddress,
          keccak256(toHex(feed.feedType)),
        ]
      )
    );
  });

  const feedsHash = keccak256(encodeAbiParameters(
    feedHashes.map(() => ({ type: 'bytes32' })),
    feedHashes
  ));

  return keccak256(
    encodeAbiParameters(
      [
        { type: 'bytes32' },
        { type: 'uint256' },
        { type: 'uint256' },
        { type: 'uint256' },
        { type: 'bytes32' },
        { type: 'bytes32' },
      ],
      [
        keccak256(toHex('PrivateIntent(uint256 totalAmount,uint256 exactFrequency,uint256 numChunks,bytes32 salt,FeedInfo[] oracleFeeds)FeedInfo(FeedTemplate feedTemplate,address feedAddress,string feedType)FeedTemplate(string name,string expression,string[] parameters,string[] secrets,uint256 retryCount)')),
        privateIntent.totalAmount,
        privateIntent.exactFrequency,
        privateIntent.numChunks,
        privateIntent.salt,
        feedsHash,
      ]
    )
  );
}

signDCAIntent().catch(console.error);

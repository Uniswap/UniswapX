// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CommonBase} from "forge-std/Base.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2} from "forge-std/console2.sol";
import {DCAIntent, PrivateIntent, OutputAllocation, FeedInfo, FeedTemplate} from "src/v4/hooks/dca/DCAStructs.sol";

contract FFISignDCAIntent is CommonBase {
    using stdJson for string;

    struct SignResult {
        bytes signature;
        bytes32 structHash;
    }

    function ffi_signDCAIntent(uint256 privateKey, address verifyingContract, uint256 chainId, DCAIntent memory intent)
        public
        returns (SignResult memory)
    {
        // Build arrays separately
        string memory allocationsJson = _buildAllocationsArray(intent.outputAllocations);
        string memory feedsJson = _buildFeedsArray(intent.privateIntent.oracleFeeds);

        // Build privateIntent
        string memory privateIntentJson = _buildPrivateIntent(intent.privateIntent, feedsJson);

        // Build intent fields in parts
        string memory intentPart1 = _buildIntentPart1(intent);
        string memory intentPart2 = _buildIntentPart2(intent, allocationsJson, privateIntentJson);

        // Combine everything
        string memory jsonObj = string.concat(
            '{"privateKey":"',
            vm.toString(privateKey),
            '","verifyingContract":"',
            vm.toString(verifyingContract),
            '","chainId":',
            vm.toString(chainId),
            ',"intent":{',
            intentPart1,
            intentPart2,
            "}}"
        );

        console2.log("FFI JSON Input:");
        console2.log(jsonObj);

        // Run the JavaScript script
        string[] memory inputs = new string[](8);
        inputs[0] = "npm";
        inputs[1] = "--silent";
        inputs[2] = "--prefix";
        inputs[3] = "./test/v4/hooks/dca/js-scripts";
        inputs[4] = "run";
        inputs[5] = "sign-dca-intent";
        inputs[6] = "--";
        inputs[7] = jsonObj;

        bytes memory result = vm.ffi(inputs);

        // Parse the JSON result
        string memory resultStr = string(result);
        bytes memory signature = vm.parseJsonBytes(resultStr, ".signature");
        bytes32 structHash = vm.parseJsonBytes32(resultStr, ".structHash");

        return SignResult({signature: signature, structHash: structHash});
    }

    function _buildAllocationsArray(OutputAllocation[] memory allocations) private pure returns (string memory) {
        string memory result = "[";
        for (uint256 i = 0; i < allocations.length; i++) {
            if (i > 0) result = string.concat(result, ",");
            result = string.concat(
                result,
                '{"recipient":"',
                vm.toString(allocations[i].recipient),
                '","basisPoints":',
                vm.toString(allocations[i].basisPoints),
                "}"
            );
        }
        return string.concat(result, "]");
    }

    function _buildStringArray(string[] memory arr) private pure returns (string memory) {
        string memory result = "[";
        for (uint256 i = 0; i < arr.length; i++) {
            if (i > 0) result = string.concat(result, ",");
            result = string.concat(result, '"', arr[i], '"');
        }
        return string.concat(result, "]");
    }

    function _buildFeedTemplate(FeedTemplate memory template) private pure returns (string memory) {
        return string.concat(
            '{"name":"',
            template.name,
            '","expression":"',
            template.expression,
            '","parameters":',
            _buildStringArray(template.parameters),
            ',"secrets":',
            _buildStringArray(template.secrets),
            ',"retryCount":',
            vm.toString(template.retryCount),
            "}"
        );
    }

    function _buildFeedsArray(FeedInfo[] memory feeds) private pure returns (string memory) {
        string memory result = "[";
        for (uint256 i = 0; i < feeds.length; i++) {
            if (i > 0) result = string.concat(result, ",");
            result = string.concat(
                result,
                '{"feedTemplate":',
                _buildFeedTemplate(feeds[i].feedTemplate),
                ',"feedAddress":"',
                vm.toString(feeds[i].feedAddress),
                '","feedType":"',
                feeds[i].feedType,
                '"}'
            );
        }
        return string.concat(result, "]");
    }

    function _buildPrivateIntent(PrivateIntent memory p, string memory feedsJson) private pure returns (string memory) {
        return string.concat(
            '{"totalAmount":"',
            vm.toString(p.totalAmount),
            '","exactFrequency":"',
            vm.toString(p.exactFrequency),
            '","numChunks":"',
            vm.toString(p.numChunks),
            '","salt":"',
            vm.toString(p.salt),
            '","oracleFeeds":',
            feedsJson,
            "}"
        );
    }

    function _buildIntentPart1(DCAIntent memory intent) private pure returns (string memory) {
        return string.concat(
            '"swapper":"',
            vm.toString(intent.swapper),
            '","nonce":"',
            vm.toString(intent.nonce),
            '","chainId":"',
            vm.toString(intent.chainId),
            '","hookAddress":"',
            vm.toString(intent.hookAddress),
            '","isExactIn":',
            intent.isExactIn ? "true" : "false",
            ',"inputToken":"',
            vm.toString(intent.inputToken),
            '","outputToken":"',
            vm.toString(intent.outputToken),
            '","cosigner":"',
            vm.toString(intent.cosigner),
            '",'
        );
    }

    function _buildIntentPart2(DCAIntent memory intent, string memory allocationsJson, string memory privateIntentJson)
        private
        pure
        returns (string memory)
    {
        return string.concat(
            '"minPeriod":"',
            vm.toString(intent.minPeriod),
            '","maxPeriod":"',
            vm.toString(intent.maxPeriod),
            '","minChunkSize":"',
            vm.toString(intent.minChunkSize),
            '","maxChunkSize":"',
            vm.toString(intent.maxChunkSize),
            '","minPrice":"',
            vm.toString(intent.minPrice),
            '","deadline":"',
            vm.toString(intent.deadline),
            '","outputAllocations":',
            allocationsJson,
            ',"privateIntent":',
            privateIntentJson
        );
    }
}

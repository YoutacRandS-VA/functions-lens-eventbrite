// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Types} from "src/vendor/lens/v2/libraries/constants/Types.sol";
import {IPublicationActionModule} from "src/vendor/lens/v2/interfaces/IPublicationActionModule.sol";
import {IModuleGlobals} from "src/vendor/lens/v2/interfaces/IModuleGlobals.sol";
import {HubRestricted} from "src/vendor/lens/v2/base/HubRestricted.sol";
import {FunctionsClient} from "src/vendor/chainlink/v0.8/functions/dev/v1_0_0/FunctionsClient.sol";
import {FunctionsRequest} from "src/vendor/chainlink/v0.8/functions/dev/v1_0_0/libraries/FunctionsRequest.sol";

contract DiscountPublicationAction is
    HubRestricted,
    IPublicationActionModule,
    FunctionsClient
{
    using FunctionsRequest for FunctionsRequest.Request;

    struct RequestDetails {
        uint8 donHostedSecretsSlotID;
        uint64 donHostedSecretsVersion;
        uint64 quantityAvailable;
        bytes32 percentageOff;
    }

    uint64 internal immutable i_subscriptionId;
    uint32 internal immutable i_callbackGasLimit;
    address internal immutable i_moduleGlobals;
    bytes32 internal immutable i_donId;

    RequestDetails internal s_requestDetails;

    mapping(bytes32 requestId => bytes32 msgSenderEventId)
        internal s_functionsRequests;
    mapping(bytes32 msgSenderEventId => bytes) internal s_discountCodes;

    event Request(bytes32 indexed requestId);
    event DiscountCode(bytes indexed discountCode);
    event SetRequestDetails(
        uint8 donHostedSecretsSlotID,
        uint64 donHostedSecretsVersion
    );

    error Unauthorized();

    constructor(
        address hub,
        address moduleGlobals,
        address router,
        uint64 subscriptionId,
        uint32 callbackGasLimit,
        bytes32 donId
    ) HubRestricted(hub) FunctionsClient(router) {
        i_moduleGlobals = moduleGlobals;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        i_donId = donId;
    }

    function initializePublicationAction(
        uint256 /*profileId*/,
        uint256 /*pubId*/,
        address /*transactionExecutor*/,
        bytes calldata data
    ) external override onlyHub returns (bytes memory) {
        (
            uint8 donHostedSecretsSlotID,
            uint64 donHostedSecretsVersion,
            bytes32 percentageOff,
            uint64 quantityAvailable
        ) = abi.decode(data, (uint8, uint64, bytes32, uint64));

        s_requestDetails.donHostedSecretsSlotID = donHostedSecretsSlotID;
        s_requestDetails.donHostedSecretsVersion = donHostedSecretsVersion;
        s_requestDetails.quantityAvailable = quantityAvailable;
        s_requestDetails.percentageOff = percentageOff;

        return data;
    }

    function processPublicationAction(
        Types.ProcessActionParams calldata processActionParams
    ) external override onlyHub returns (bytes memory) {
        (
            string memory organizationId,
            string memory eventId,
            string memory javaScriptSource
        ) = abi.decode(
                processActionParams.actionModuleData,
                (string, string, string)
            );

        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(javaScriptSource);

        req.addDONHostedSecrets(
            s_requestDetails.donHostedSecretsSlotID,
            s_requestDetails.donHostedSecretsVersion
        );

        string[] memory args = new string[](5);
        args[0] = organizationId;
        args[1] = eventId;
        args[2] = string(
            abi.encodePacked(processActionParams.actorProfileOwner)
        );
        args[3] = string(abi.encodePacked(s_requestDetails.percentageOff));
        args[4] = string(abi.encodePacked(s_requestDetails.quantityAvailable));

        req.setArgs(args);

        bytes32 requestId = _sendRequest(
            req.encodeCBOR(),
            i_subscriptionId,
            i_callbackGasLimit,
            i_donId
        );

        bytes32 userToEventIdRelation = keccak256(
            abi.encodePacked(processActionParams.actorProfileOwner, eventId)
        );
        s_functionsRequests[requestId] = userToEventIdRelation;

        emit Request(requestId);

        return abi.encode(requestId);
    }

    function setRequestDetails(
        uint8 donHostedSecretsSlotID,
        uint64 donHostedSecretsVersion
    ) external {
        if (msg.sender != IModuleGlobals(i_moduleGlobals).getGovernance()) {
            revert Unauthorized();
        }

        s_requestDetails.donHostedSecretsSlotID = donHostedSecretsSlotID;
        s_requestDetails.donHostedSecretsVersion = donHostedSecretsVersion;

        emit SetRequestDetails(donHostedSecretsSlotID, donHostedSecretsVersion);
    }

    function getDiscountCode(
        address user,
        string memory eventId
    ) external view returns (string memory) {
        bytes32 userToEventIdRelation = keccak256(
            abi.encodePacked(user, eventId)
        );

        return string(s_discountCodes[userToEventIdRelation]);
    }

    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory /*err*/
    ) internal override {
        s_discountCodes[s_functionsRequests[requestId]] = response;
        emit DiscountCode(response);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;
import "./SystemToken.sol";
import "./WrapToken.sol";
contract dao {
    SystemToken internal token;
    WrapToken internal wrapToken;
    uint256 public priceProfi = 2;
    uint256 public priceRTK = 3;
    struct Proposal {
        uint256 forVotes; // голос за
        uint256 againstVotes; // голос против
        uint256 startTime; // начальное время предложения
        uint256 endTime; // конечное время предложения (указываем минуты)
        ProposalType proposalType; // тип предложения
        QuorumMechanism quorumType; // тип кворума для предложения
        address target; // на кого будет действовать предложение после окончания
        address proposer; // инициатор предложения, нужен для удаления
        uint256 needVotes; // сколько необходимо для реализации предложения (quorum)
        uint256 valueForChange; // нужен для смены СВАП или РТК токена
        mapping(address => bool) hasVoted; // проверка на голосующего (кто проголосовал, а кто нет), чтобы вернуть токены
        bool hasDeleted; // предложение удалено?
    }
    uint256 internal proposalCount; // количество всех предложений
    mapping(uint256 => Proposal) internal proposals; // все предложения
    mapping(address => bool) private daoMembers; // список участников DAO
    mapping(uint256 => address[]) internal proposalVoters; // список адресов проголосовавших для каждого предложения
    mapping(uint256 => mapping(address => uint256)) internal voterAmount; // хранение токенов для каждого voter'a
    mapping(uint => address[]) internal proposalDelegate; // список адресов делегировавших на предложения 
    mapping(uint => mapping(address => uint)) internal delegateAmount; // uint - тип предложения, и кол-во токенов адресу
    mapping(address => uint) internal delegatedWeight; // сколько RTK делегировали ДАО-адресу
    enum ProposalType {
        A, // 0 - инвестиция в стартап
        B, // 1 - дополнительная инвестиция
        C, // 2 - добавить участника
        D, // 3 - удалить участника
        E, // 4 - управление SystemToken
        F // 5 - управление wrap-token
    }
    enum QuorumMechanism {
        SimpleMajority, // 50% + 1
        SuperMajority, // 2/3
        Weighted // Взвешенное
    }
    modifier OnlyDaoMember() {
        require(daoMembers[msg.sender], "Not a DAO member");
        _;
    }
    constructor(
        address _systemToken,
        address _wrapToken,
        address[] memory _initialMembers
    ) {
        token = SystemToken(_systemToken);
        wrapToken = WrapToken(_wrapToken);
        // Добавляем всех начальных участников
        for (uint256 i = 0; i < _initialMembers.length; i++) {
            daoMembers[_initialMembers[i]] = true;
        }
    }
    function createProposal(
        ProposalType _proposalType,
        QuorumMechanism _quorumType,
        address _target, // на кого будет действовать предложение
        uint256 _durationMinutes, // time in minutes
        uint256 _value,
        uint256 _valueForChange // нужен для смены СВАП или РТК токена
    ) public OnlyDaoMember returns (uint256) {
        uint256 id = proposalCount++;
        proposals[id].proposalType = _proposalType;
        proposals[id].quorumType = _quorumType;
        proposals[id].target = _target;
        proposals[id].needVotes = _value;
        proposals[id].valueForChange = _valueForChange;
        proposals[id].proposer = msg.sender;
        // Проверка на тип кворума при создании предложения
        if (
            _proposalType == ProposalType.A || _proposalType == ProposalType.B
        ) {
            require(
                _quorumType == QuorumMechanism.Weighted,
                "Quorum must be only for investing to StartUp"
            );
        } else {
            require(
                _quorumType != QuorumMechanism.Weighted,
                "Invalid type Quorum"
            );
        }
        // время в секундах
        proposals[id].startTime = block.timestamp;
        proposals[id].endTime = block.timestamp + (_durationMinutes * 60);
        return id;
    }
    function vote(
        uint256 _proposalId,
        bool _support,
        uint256 _value
    ) public OnlyDaoMember {
        require(
            block.timestamp >= proposals[_proposalId].startTime,
            "Voting not started"
        );
        require(
            block.timestamp <= proposals[_proposalId].endTime,
            "Voting ended"
        );
        require(_value > 0, "Must vote with tokens");
        Proposal storage proposal = proposals[_proposalId];
        token.transferFrom(msg.sender, address(this), _value);
        uint voteWeight = (_value / priceProfi) +
            (delegatedWeight[msg.sender] / priceRTK);
        //          СОХРАНЯЕМ ИНФОРМАЦИЮ О ГОЛОСУЮЩЕМ
        proposalVoters[_proposalId].push(msg.sender);
        voterAmount[_proposalId][msg.sender] = _value;
        // Засчитываем голос
        if (_support) {
            proposal.forVotes += voteWeight;
        } else {
            proposal.againstVotes += voteWeight;
        }
        // Выполнение тип предложения
        if (
            proposal.needVotes <= proposal.forVotes && checkQuorum(_proposalId)
        ) {
            if (
                proposal.proposalType == ProposalType.A ||
                proposal.proposalType == ProposalType.B
            ) {
                token.transferFrom(address(this),proposal.target,proposal.needVotes);
            } else if (proposal.proposalType == ProposalType.C) {
                daoMembers[proposal.target] = true;
            } else if (proposal.proposalType == ProposalType.D) {
                daoMembers[proposal.target] = false;
            } else if (proposal.proposalType == ProposalType.E) {
                priceProfi = proposal.valueForChange;
            } else if (proposal.proposalType == ProposalType.F) {
                priceRTK = proposal.valueForChange;
            }
        }
        proposals[_proposalId].hasVoted[msg.sender] = true;
    }
    function delegate(
        uint _proposalId,
        address daoMember,
        uint value
    ) external returns (bool) {
        require(!daoMembers[msg.sender], unicode"вы в дао");
        require(wrapToken.balanceOf(msg.sender) > 0, unicode"токенов нет");
        wrapToken.transferFrom(msg.sender, address(this), value);
        proposalDelegate[_proposalId].push(msg.sender);
        delegateAmount[_proposalId][msg.sender] += value;
        delegatedWeight[daoMember] += value;
        return true;
    }
    function checkQuorum(uint256 _proposalId) internal view returns (bool) {
        Proposal storage proposal = proposals[_proposalId];
        uint totalVotes = proposal.againstVotes + proposal.forVotes;
        if (proposal.quorumType == QuorumMechanism.Weighted) {
            return proposal.forVotes > proposal.againstVotes;
        }
        if (proposal.quorumType == QuorumMechanism.SimpleMajority) {
            return proposal.forVotes * 2 > totalVotes;
        } else if (proposal.quorumType == QuorumMechanism.SuperMajority) {
            return proposal.forVotes * 3 > totalVotes * 2;
        }
        return false;
    }
    function deleteProposal(uint256 _proposalId) external OnlyDaoMember {
        Proposal storage proposal = proposals[_proposalId];
        require(
            msg.sender == proposal.proposer,
            "Only proposer can delete"
        );
        require(
            block.timestamp <= proposal.endTime,
            "Voting already ended"
        );
        proposal.hasDeleted = true;
        // Возвращаем токены DAO MEMBERS
        address[] memory voters = proposalVoters[_proposalId];
        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];
            uint256 amount = voterAmount[_proposalId][voter];
            if (amount > 0) {
                token.transfer(voter, amount);
                voterAmount[_proposalId][voter] = 0;
            }
        }
        // Return tokens NOT DAO
        address[] memory delegateVoters = proposalDelegate[_proposalId];
        for (uint256 i = 0; i < delegateVoters.length; i++) {
            address delegator = delegateVoters[i];
            uint256 amount = delegateAmount[_proposalId][delegator];

            if (amount > 0) {
                wrapToken.transferFrom(address(this), delegator, amount);
                delegateAmount[_proposalId][delegator] = 0;
            }
        }
    }
    function getProposal(
        uint256 _proposalId
    )
        public
        view
        returns (
            uint needVotes,
            uint forVotes,
            uint againstVotes,
            uint remainingMinutes,
            uint remainingSeconds,
            ProposalType proposalType,
            QuorumMechanism quorum
        )
    {
        Proposal storage proposal = proposals[_proposalId];
        uint256 totalRemainingSeconds;
        // Вычисляем оставшееся время
        if (block.timestamp < proposals[_proposalId].endTime) {
            totalRemainingSeconds =
                proposals[_proposalId].endTime - block.timestamp;
            remainingMinutes = totalRemainingSeconds / 60; // minutes
            remainingSeconds = totalRemainingSeconds % 60; // seconds
        }
        // Проверка на количество голосов + выполнено ли предложение
        if ( 
            proposal.forVotes >= proposal.needVotes ||
            proposal.hasDeleted == true
        ) {
            remainingMinutes = 0;
            remainingSeconds = 0;
        }
        return (
            proposal.needVotes,
            proposal.forVotes,
            proposal.againstVotes,
            remainingMinutes,
            remainingSeconds,
            proposal.proposalType,
            proposal.quorumType
        );
    }
    function buyTokensEth() external payable {
        uint256 amount = msg.value / 1 ether;
        wrapToken.transferFrom(address(wrapToken), msg.sender, amount);
    }
}
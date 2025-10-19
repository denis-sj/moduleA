// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./tokens/SystemToken.sol";
import "./tokens/WrapToken.sol";

contract TokenWeightedGovernor {
    SystemToken internal token;
    WrapToken internal wrapToken;

    /*
    description - описание
    forVotes - голос за
    againstVotes - голос против
    startTime - начальное время предложения 
    endTime - сколько будет длиться предложение (указываем минуты)
    proposalType -  тип предложения
    quorumType - тип кворума для предложения 
    executed - предложение активно или нет
    target - куда будет действовать предложение после окончания
    proposer - инициатор предложения
    value - значение
    hasVotes - голоса адрессов
 */
    struct Proposal {
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 startTime;
        uint256 endTime;
        ProposalType proposalType;
        QuorumMechanism quorumType;
        bool executed;
        address target;
        address proposer;
        uint256 value;
        mapping(address => bool) hasVoted;
    }

    uint256 public proposalCount; // количество всех предложений

    mapping(uint256 => Proposal) internal proposals; // все предложения
    mapping(address => bool) public daoMembers; // список участников DAO
    mapping(uint256 => address[]) public proposalVoters; // список адресов проголосовавших для каждого предложения
    mapping(uint256 => mapping(address => uint256)) public voterAmount; // хранение токенов для каждого voter'a

    enum ProposalType {
        A, // 0 - инвестиция в стартап
        B, // 1 - дополнительная инвестиция
        C, // 2 - добавить участника1
        D, // 3 - удалить участника
        E, // 4 - управление SystemToken
        F // 5 - управление wrap-token
    }

    enum QuorumMechanism {
        SimpleMajority, // 50% + 1
        SuperMajority, // 2/3
        Weighted // Взвешенное
    }

    // ============ EVENT ============
    event ProposalCreated(
        uint256 indexed proposalId,
        ProposalType proposalType,
        string description
    );
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        bool support,
        uint256 amount
    );
    event ProposalExecuted(uint256 indexed proposalId);

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

    // ============ СОЗДАНИЕ ПРЕДЛОЖЕНИЯ ============
    function createProposal(
        string memory _description,
        ProposalType _proposalType,
        QuorumMechanism _quorumType,
        address _target, // на кого будет действовать предложение
        uint256 _durationMinutes, // time in minutes
        uint256 _value
    ) public OnlyDaoMember returns (uint256) {
        // проверки
        require(_durationMinutes > 0, "Duration must be > 0");
        require(bytes(_description).length > 0, "Description required");

        uint256 id = proposalCount++;
        Proposal storage proposal = proposals[id];
        proposal.description = _description;
        proposal.proposalType = _proposalType;
        proposal.quorumType = _quorumType;
        proposal.target = _target;
        proposal.value = _value;
        proposal.proposer = msg.sender; // инициатор предложения

        // Проверка на тип кворума при создании предложения, можно было автоматически это реализовать, но пока пусть так будет
        if (
            _proposalType == ProposalType.A || _proposalType == ProposalType.B
        ) {
            require(
                _quorumType == QuorumMechanism.Weighted,
                "Investment proposals must use Weighted quorum"
            );
        } else {
            require(
                _quorumType != QuorumMechanism.Weighted,
                "Only investment proposals can use Weighted quorum"
            );
        }

        // время в секундах
        proposal.startTime = block.timestamp;
        proposal.endTime = block.timestamp + (_durationMinutes * 60);

        emit ProposalCreated(id, _proposalType, _description);
        return id;
    }

    // ============ ГОЛОСОВАНИЕ ============
    function vote(
        uint256 _proposalId,
        bool _support,
        uint256 _value
    ) public {
        Proposal storage proposal = proposals[_proposalId];

        // проверки
        require(block.timestamp >= proposal.startTime, "Voting not started");
        require(block.timestamp <= proposal.endTime, "Voting ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(_value > 0, "Must vote with tokens");

        uint256 voteWeight;
        // проверка на участника DAO
        if (daoMembers[msg.sender]) {
            require(_value >= 3, "Minimum 3 tokens PROFI required ");

            // блокируем токены в контракт
            // но перед блокировкой токенов в контракт, 
            // необходимо дать разрешение (approve) с msg.sender в контракт токены
            token.transferFrom(msg.sender, address(this), _value);
            voteWeight = _value / 3;
        } else {
            require(_value >= 6, "Minimum 6 tokens PROFI required");
            wrapToken.transferFrom(msg.sender, address(this), _value);
            voteWeight = _value / 6;
        }

        //          СОХРАНЯЕМ ИНФОРМАЦИЮ О ГОЛОСУЮЩЕМ
        proposalVoters[_proposalId].push(msg.sender);
        voterAmount[_proposalId][msg.sender] = _value;

        // Засчитываем голос
        if (_support) {
            proposal.forVotes += voteWeight;
        } else {
            proposal.againstVotes += voteWeight;
        }

        proposal.hasVoted[msg.sender] = true;

        emit VoteCast(msg.sender, _proposalId, _support, voteWeight);
    }

    //          ============ EXECUTE ============
    /**
     *  Выполнить предложение после успешного голосования
     */
    function execute(uint256 _proposalId) external payable {
        Proposal storage proposal = proposals[_proposalId];

        // Проверка 1: Голосование закончилось
        require(block.timestamp > proposal.endTime, "Voting not ended");

        // Проверка 2: Ещё не выполнено
        require(!proposal.executed, "Already executed");

        // Проверка 3: Предложение принято (больше "За")
        require(
            proposal.forVotes > proposal.againstVotes,
            "Proposal failed (forVotes >= againstVotes)"
        );

        // Test 4: Проверка на указание кворума
        require(checkQuorum(_proposalId), "Quorum not reached");

        // Отмечаем как выполненное
        proposal.executed = true;

        // Выполняем действие в зависимости от типа
        if (
            proposal.proposalType == ProposalType.A ||
            proposal.proposalType == ProposalType.B
        ) {
            // Инвестиция: отправить ETH
            _executeInvestment(proposal);
        } else if (proposal.proposalType == ProposalType.C) {
            // Добавить участника
            _executeAddMember(proposal);
        } else if (proposal.proposalType == ProposalType.D) {
            // Удалить участника
            _executeRemoveMember(proposal);
        } else if (proposal.proposalType == ProposalType.E) {
            // Управление токеном
            _executeManageToken(proposal);
        } else if (proposal.proposalType == ProposalType.F) {
            // Управление ВРАП-ТОКЕНОМ
            _executeManageWrapToken(proposal);
        }

        emit ProposalExecuted(_proposalId);
    }

    // ============ Execute ФУНКЦИИ ВЫПОЛНЕНИЯ ============
    function _executeInvestment(Proposal storage proposal) internal {
        require(proposal.target != address(0), "Invalid target");
        require(proposal.value > 0, "Invalid amount");

        // Отправляем ETH стартапу
        (bool success, ) = proposal.target.call{value: proposal.value}("");
        require(success, "ETH transfer failed");
    }

    function _executeAddMember(Proposal storage proposal) internal {
        require(proposal.target != address(0), "Invalid member address");
        daoMembers[proposal.target] = true;
    }

    function _executeRemoveMember(Proposal storage proposal) internal {
        require(proposal.target != address(0), "Invalid member address");
        daoMembers[proposal.target] = false;
    }

    function _executeManageToken(Proposal storage proposal) internal {
        // управление SystemToken, какая тут реализация?
    }

    function _executeManageWrapToken(Proposal storage proposal) internal {
        // тут должна быть логика враптокена, пока только комментарий
    }

    // ============ ФУНКЦИЯ checkQuorum ============
    function checkQuorum(uint256 _proposalId) internal view returns (bool) {
        Proposal storage _proposal = proposals[_proposalId];

        uint256 totalVotes = _proposal.forVotes + _proposal.againstVotes;

        if (totalVotes == 0) return false;

        if (_proposal.quorumType == QuorumMechanism.SimpleMajority) {
            return _proposal.forVotes > _proposal.againstVotes;
        } else if (_proposal.quorumType == QuorumMechanism.SuperMajority) {
            return _proposal.forVotes >= (totalVotes * 2) / 3;
        } else if (_proposal.quorumType == QuorumMechanism.Weighted) {
            return _proposal.forVotes > _proposal.againstVotes;
        }

        return false;
    }

    function deleteProposal(uint256 _proposalId) external OnlyDaoMember {
        Proposal storage proposal = proposals[_proposalId];
        require(msg.sender == proposal.proposer, "Only proposer can delete");
        require(block.timestamp <= proposal.endTime, "Voting already ended");
        require(!proposal.executed, "Already executed or deleted proposal");

        // Помечаем как удалённое
        proposal.executed = true;

        // Возвращаем токены всем проголосовавшим
        address[] memory voters = proposalVoters[_proposalId];

        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];
            uint256 amount = voterAmount[_proposalId][voter];

            if (amount > 0) {
                bool success;
                if (daoMembers[voter]) {
                    success = token.transfer(voter, amount);
                } else {
                    success = wrapToken.transfer(voter, amount);
                }
                require(success, "Token refund failed");
                voterAmount[_proposalId][voter] = 0;
            }
        }
    }

    // ============= Информация о предложении =============
    function getProposal(uint256 _proposalId)
        public
        view
        returns (
            string memory description,
            uint256 needVotes,
            uint256 forVotes,
            uint256 againstVotes,
            uint256 remainingSeconds, // <- Осталось seconds
            uint256 remainingMinutes, // <- Осталось minutes
            ProposalType proposalType,
            bool executed
        )
    {
        Proposal storage proposal = proposals[_proposalId];

        uint256 totalRemainingSeconds;
        uint256 remainingSeconds;
        uint256 remainingMinutes;

        // Вычисляем оставшееся время
        if (block.timestamp < proposal.endTime) {
            totalRemainingSeconds = proposal.endTime - block.timestamp;

            // Minutes
            remainingMinutes = totalRemainingSeconds / 60;

            // Seconds
            remainingSeconds = totalRemainingSeconds % 60;
        }

        return (
            proposal.description,
            proposal.value,
            proposal.forVotes,
            proposal.againstVotes,
            remainingSeconds,
            remainingMinutes,
            proposal.proposalType,
            proposal.executed
        );
    }

    // Узнать, голосовал адрес или нет
    function hasVoted(uint256 _proposalId, address _voter)
        public
        view
        returns (bool)
    {
        return proposals[_proposalId].hasVoted[_voter];
    }
}

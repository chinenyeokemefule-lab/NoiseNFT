;; title: NoiseNFT - Decibel-based Noise Pollution Trading System
;; version: 1.0.0
;; summary: A comprehensive noise allowance trading system for urban sound management
;; description: This contract implements a decibel-based noise pollution trading system
;;              that allows neighborhoods to trade noise allowances, manage quiet zones,
;;              and integrate with construction permits through community governance.

;; traits
(define-trait nft-trait
  (
    ;; Last token ID, limited to uint range
    (get-last-token-id () (response uint uint))
    
    ;; URI for metadata
    (get-token-uri (uint) (response (optional (string-ascii 256)) uint))
    
    ;; Owner of a given token identifier
    (get-owner (uint) (response (optional principal) uint))
    
    ;; Transfer from the sender to a new principal
    (transfer (uint principal principal) (response bool uint))
  )
)

;; token definitions
(define-non-fungible-token noise-allowance uint)

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_AMOUNT (err u103))
(define-constant ERR_INSUFFICIENT_ALLOWANCE (err u104))
(define-constant ERR_INVALID_DECIBEL (err u105))
(define-constant ERR_ZONE_NOT_FOUND (err u106))
(define-constant ERR_PERMIT_EXISTS (err u107))
(define-constant ERR_VOTING_PERIOD_ACTIVE (err u108))
(define-constant ERR_ALREADY_VOTED (err u109))
(define-constant ERR_INVALID_VOTE (err u110))

;; Maximum decibel levels
(define-constant MAX_DECIBEL u120)
(define-constant MIN_DECIBEL u30)
(define-constant QUIET_ZONE_LIMIT u50)

;; Voting constants
(define-constant VOTING_PERIOD u144) ;; ~24 hours in blocks
(define-constant MIN_VOTES_REQUIRED u10)

;; data vars
(define-data-var last-token-id uint u0)
(define-data-var contract-uri (optional (string-ascii 256)) (some "https://noisenft.city/metadata"))
(define-data-var next-zone-id uint u1)
(define-data-var next-permit-id uint u1)
(define-data-var next-proposal-id uint u1)

;; data maps
;; Zone management
(define-map zones
  uint
  {
    name: (string-ascii 50),
    max-decibel: uint,
    current-usage: uint,
    is-quiet-zone: bool,
    premium-multiplier: uint
  }
)

(define-map zone-owners
  uint ;; zone-id
  principal
)

;; Allowance tracking
(define-map allowances
  { zone-id: uint, owner: principal }
  {
    total-allowance: uint,
    used-allowance: uint,
    expiry-block: uint
  }
)

;; Noise monitoring data
(define-map noise-readings
  { zone-id: uint, timestamp: uint }
  {
    decibel-level: uint,
    reporter: principal,
    verified: bool
  }
)

;; Construction permits
(define-map construction-permits
  uint ;; permit-id
  {
    zone-id: uint,
    applicant: principal,
    requested-decibels: uint,
    duration-blocks: uint,
    approved: bool,
    start-block: uint,
    end-block: uint,
    fee-paid: uint
  }
)

;; Trading functionality
(define-map trade-offers
  uint ;; token-id
  {
    seller: principal,
    price: uint,
    zone-id: uint,
    decibel-amount: uint,
    active: bool
  }
)

;; Community voting
(define-map proposals
  uint ;; proposal-id
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    zone-id: uint,
    proposed-max-decibel: uint,
    proposer: principal,
    start-block: uint,
    end-block: uint,
    yes-votes: uint,
    no-votes: uint,
    executed: bool
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  bool ;; true for yes, false for no
)

;; Premium pricing for quiet zones
(define-map quiet-zone-premiums
  uint ;; zone-id
  uint ;; premium percentage (100 = 100%)
)
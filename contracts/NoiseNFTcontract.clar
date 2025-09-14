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
;; public functions

;; Zone Management
(define-public (create-zone (name (string-ascii 50)) (max-decibel uint) (is-quiet-zone bool))
  (let
    (
      (zone-id (var-get next-zone-id))
      (premium (if is-quiet-zone u200 u100)) ;; 200% premium for quiet zones
    )
    (asserts! (and (>= max-decibel MIN_DECIBEL) (<= max-decibel MAX_DECIBEL)) ERR_INVALID_DECIBEL)
    (asserts! (or (not is-quiet-zone) (<= max-decibel QUIET_ZONE_LIMIT)) ERR_INVALID_DECIBEL)
    
    (try! (map-set zones zone-id {
      name: name,
      max-decibel: max-decibel,
      current-usage: u0,
      is-quiet-zone: is-quiet-zone,
      premium-multiplier: premium
    }))
    
    (map-set zone-owners zone-id tx-sender)
    (var-set next-zone-id (+ zone-id u1))
    
    (if is-quiet-zone
      (map-set quiet-zone-premiums zone-id premium)
      true
    )
    
    (ok zone-id)
  )
)

;; Allowance Management
(define-public (allocate-allowance (zone-id uint) (recipient principal) (amount uint) (duration-blocks uint))
  (let
    (
      (zone (unwrap! (map-get? zones zone-id) ERR_ZONE_NOT_FOUND))
      (zone-owner (unwrap! (map-get? zone-owners zone-id) ERR_UNAUTHORIZED))
      (expiry-block (+ block-height duration-blocks))
    )
    (asserts! (is-eq tx-sender zone-owner) ERR_UNAUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    
    (map-set allowances 
      { zone-id: zone-id, owner: recipient }
      {
        total-allowance: amount,
        used-allowance: u0,
        expiry-block: expiry-block
      }
    )
    
    (ok true)
  )
)

;; Noise Monitoring
(define-public (report-noise-level (zone-id uint) (decibel-level uint))
  (let
    (
      (zone (unwrap! (map-get? zones zone-id) ERR_ZONE_NOT_FOUND))
      (timestamp block-height)
    )
    (asserts! (and (>= decibel-level MIN_DECIBEL) (<= decibel-level MAX_DECIBEL)) ERR_INVALID_DECIBEL)
    
    (map-set noise-readings 
      { zone-id: zone-id, timestamp: timestamp }
      {
        decibel-level: decibel-level,
        reporter: tx-sender,
        verified: false
      }
    )
    
    ;; Update zone current usage
    (map-set zones zone-id
      (merge zone { current-usage: decibel-level })
    )
    
    (ok true)
  )
)

;; Construction Permits
(define-public (apply-for-permit (zone-id uint) (requested-decibels uint) (duration-blocks uint))
  (let
    (
      (permit-id (var-get next-permit-id))
      (zone (unwrap! (map-get? zones zone-id) ERR_ZONE_NOT_FOUND))
      (fee (calculate-permit-fee zone-id requested-decibels duration-blocks))
    )
    (asserts! (and (>= requested-decibels MIN_DECIBEL) (<= requested-decibels MAX_DECIBEL)) ERR_INVALID_DECIBEL)
    
    (map-set construction-permits permit-id {
      zone-id: zone-id,
      applicant: tx-sender,
      requested-decibels: requested-decibels,
      duration-blocks: duration-blocks,
      approved: false,
      start-block: u0,
      end-block: u0,
      fee-paid: fee
    })
    
    (var-set next-permit-id (+ permit-id u1))
    (ok permit-id)
  )
)

(define-public (approve-permit (permit-id uint))
  (let
    (
      (permit (unwrap! (map-get? construction-permits permit-id) ERR_NOT_FOUND))
      (zone-id (get zone-id permit))
      (zone-owner (unwrap! (map-get? zone-owners zone-id) ERR_UNAUTHORIZED))
    )
    (asserts! (is-eq tx-sender zone-owner) ERR_UNAUTHORIZED)
    (asserts! (not (get approved permit)) ERR_PERMIT_EXISTS)
    
    (map-set construction-permits permit-id
      (merge permit { 
        approved: true,
        start-block: block-height,
        end-block: (+ block-height (get duration-blocks permit))
      })
    )
    
    (ok true)
  )
)

;; Trading System
(define-public (create-trade-offer (zone-id uint) (decibel-amount uint) (price uint))
  (let
    (
      (token-id (+ (var-get last-token-id) u1))
      (allowance-data (unwrap! (map-get? allowances { zone-id: zone-id, owner: tx-sender }) ERR_NOT_FOUND))
    )
    (asserts! (>= (- (get total-allowance allowance-data) (get used-allowance allowance-data)) decibel-amount) ERR_INSUFFICIENT_ALLOWANCE)
    (asserts! (> price u0) ERR_INVALID_AMOUNT)
    
    (try! (nft-mint? noise-allowance token-id tx-sender))
    (var-set last-token-id token-id)
    
    (map-set trade-offers token-id {
      seller: tx-sender,
      price: price,
      zone-id: zone-id,
      decibel-amount: decibel-amount,
      active: true
    })
    
    (ok token-id)
  )
)

(define-public (accept-trade-offer (token-id uint))
  (let
    (
      (offer (unwrap! (map-get? trade-offers token-id) ERR_NOT_FOUND))
      (seller (get seller offer))
    )
    (asserts! (get active offer) ERR_NOT_FOUND)
    (asserts! (not (is-eq tx-sender seller)) ERR_UNAUTHORIZED)
    
    ;; Transfer NFT
    (try! (nft-transfer? noise-allowance token-id seller tx-sender))
    
    ;; Update allowances
    (try! (transfer-allowance (get zone-id offer) seller tx-sender (get decibel-amount offer)))
    
    ;; Deactivate offer
    (map-set trade-offers token-id
      (merge offer { active: false })
    )
    
    (ok true)
  )
)

;; Community Voting
(define-public (create-proposal (title (string-ascii 100)) (description (string-ascii 500)) (zone-id uint) (proposed-max-decibel uint))
  (let
    (
      (proposal-id (var-get next-proposal-id))
    )
    (asserts! (and (>= proposed-max-decibel MIN_DECIBEL) (<= proposed-max-decibel MAX_DECIBEL)) ERR_INVALID_DECIBEL)
    (asserts! (map-get? zones zone-id) ERR_ZONE_NOT_FOUND)
    
    (map-set proposals proposal-id {
      title: title,
      description: description,
      zone-id: zone-id,
      proposed-max-decibel: proposed-max-decibel,
      proposer: tx-sender,
      start-block: block-height,
      end-block: (+ block-height VOTING_PERIOD),
      yes-votes: u0,
      no-votes: u0,
      executed: false
    })
    
    (var-set next-proposal-id (+ proposal-id u1))
    (ok proposal-id)
  )
)

(define-public (vote-on-proposal (proposal-id uint) (vote-yes bool))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_NOT_FOUND))
      (current-vote (map-get? votes { proposal-id: proposal-id, voter: tx-sender }))
    )
    (asserts! (< block-height (get end-block proposal)) ERR_VOTING_PERIOD_ACTIVE)
    (asserts! (is-none current-vote) ERR_ALREADY_VOTED)
    
    (map-set votes { proposal-id: proposal-id, voter: tx-sender } vote-yes)
    
    (if vote-yes
      (map-set proposals proposal-id
        (merge proposal { yes-votes: (+ (get yes-votes proposal) u1) }))
      (map-set proposals proposal-id
        (merge proposal { no-votes: (+ (get no-votes proposal) u1) }))
    )
    
    (ok true)
  )
)

(define-public (execute-proposal (proposal-id uint))
  (let
    (
      (proposal (unwrap! (map-get? proposals proposal-id) ERR_NOT_FOUND))
      (zone-id (get zone-id proposal))
      (zone (unwrap! (map-get? zones zone-id) ERR_ZONE_NOT_FOUND))
      (total-votes (+ (get yes-votes proposal) (get no-votes proposal)))
    )
    (asserts! (>= block-height (get end-block proposal)) ERR_VOTING_PERIOD_ACTIVE)
    (asserts! (not (get executed proposal)) ERR_ALREADY_EXISTS)
    (asserts! (>= total-votes MIN_VOTES_REQUIRED) ERR_INVALID_VOTE)
    (asserts! (> (get yes-votes proposal) (get no-votes proposal)) ERR_INVALID_VOTE)
    
    ;; Update zone max decibel
    (map-set zones zone-id
      (merge zone { max-decibel: (get proposed-max-decibel proposal) })
    )
    
    ;; Mark proposal as executed
    (map-set proposals proposal-id
      (merge proposal { executed: true })
    )
    
    (ok true)
  )
)

;; read only functions

(define-read-only (get-zone-info (zone-id uint))
  (map-get? zones zone-id)
)

(define-read-only (get-zone-owner (zone-id uint))
  (map-get? zone-owners zone-id)
)

(define-read-only (get-allowance (zone-id uint) (owner principal))
  (map-get? allowances { zone-id: zone-id, owner: owner })
)

(define-read-only (get-noise-reading (zone-id uint) (timestamp uint))
  (map-get? noise-readings { zone-id: zone-id, timestamp: timestamp })
)

(define-read-only (get-permit-info (permit-id uint))
  (map-get? construction-permits permit-id)
)

(define-read-only (get-trade-offer (token-id uint))
  (map-get? trade-offers token-id)
)

(define-read-only (get-proposal-info (proposal-id uint))
  (map-get? proposals proposal-id)
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter })
)

(define-read-only (calculate-permit-fee (zone-id uint) (requested-decibels uint) (duration-blocks uint))
  (let
    (
      (zone (unwrap! (map-get? zones zone-id) ERR_ZONE_NOT_FOUND))
      (base-fee (* requested-decibels duration-blocks))
      (premium (if (get is-quiet-zone zone) (get premium-multiplier zone) u100))
    )
    (ok (/ (* base-fee premium) u100))
  )
)

(define-read-only (get-last-token-id)
  (ok (var-get last-token-id))
)

(define-read-only (get-token-uri (token-id uint))
  (ok (var-get contract-uri))
)

(define-read-only (get-owner (token-id uint))
  (ok (nft-get-owner? noise-allowance token-id))
)

;; private functions

(define-private (transfer-allowance (zone-id uint) (from principal) (to principal) (amount uint))
  (let
    (
      (from-allowance (unwrap! (map-get? allowances { zone-id: zone-id, owner: from }) ERR_NOT_FOUND))
      (to-allowance (default-to 
        { total-allowance: u0, used-allowance: u0, expiry-block: u0 }
        (map-get? allowances { zone-id: zone-id, owner: to })))
    )
    (asserts! (>= (- (get total-allowance from-allowance) (get used-allowance from-allowance)) amount) ERR_INSUFFICIENT_ALLOWANCE)
    
    ;; Update from allowance
    (map-set allowances { zone-id: zone-id, owner: from }
      (merge from-allowance { used-allowance: (+ (get used-allowance from-allowance) amount) }))
    
    ;; Update to allowance
    (map-set allowances { zone-id: zone-id, owner: to }
      (merge to-allowance { 
        total-allowance: (+ (get total-allowance to-allowance) amount),
        expiry-block: (max (get expiry-block from-allowance) (get expiry-block to-allowance))
      }))
    
    (ok true)
  )
)

;; NFT transfer function
(define-public (transfer (token-id uint) (sender principal) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender sender) ERR_UNAUTHORIZED)
    (try! (nft-transfer? noise-allowance token-id sender recipient))
    (ok true)
  )
)
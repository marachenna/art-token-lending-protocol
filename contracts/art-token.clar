;; art-token-lending-protocol

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          CONSTANTS                           ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-price (err u101))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          DATA VARS                           ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-data-var min-ltv-ratio uint u150)
(define-data-var current-price uint u0)
(define-data-var last-update uint u0)
(define-data-var system-paused bool false)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          DATA STORAGE                        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-map art-collateral-map
    {user: principal}      
    {art-tokens: uint})           

(define-map loan-balance
    {user: principal}      
    {balance: uint})    

(define-map accrued-fees
    {user: principal}
    {earned: uint})

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          PRICE ORACLE FUNCTIONS              ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-read-only (get-price)
    (ok (var-get current-price)))

(define-read-only (get-last-update)
    (ok (var-get last-update)))

(define-public (update-price (new-price uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> new-price u0) err-invalid-price)
        (var-set current-price new-price)
        (var-set last-update block-height)
        (ok new-price)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          READ-ONLY FUNCTIONS                 ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-read-only (get-art-collateral (user principal))
    (default-to u0 (get art-tokens (map-get? art-collateral-map {user: user}))))

(define-read-only (get-loan-balance (user principal))
    (default-to u0 (get balance (map-get? loan-balance {user: user}))))

(define-read-only (calculate-collateral-value (art-amount uint))
    (* art-amount (unwrap-panic (get-price))))

(define-read-only (is-collateral-sufficient (user principal) (loan-amount uint))
    (let ((collateral (get-art-collateral user))
          (art-price (unwrap-panic (get-price)))
          (min-ratio (var-get min-ltv-ratio)))
        (>= (* collateral art-price) (* loan-amount (/ min-ratio u100)))))

(define-read-only (check-ltv-ratio (user principal))
    (let ((collateral (get-art-collateral user))
          (balance (get-loan-balance user))
          (art-price (unwrap-panic (get-price))))
        (if (is-eq balance u0)
            (err "No active loans")
            (ok (/ (* collateral art-price) balance)))))

(define-read-only (is-paused)
    (var-get system-paused))

(define-read-only (get-min-ltv-ratio)
    (var-get min-ltv-ratio))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          PUBLIC FUNCTIONS                    ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (lock-art-collateral (art-amount uint))
    (begin
        (asserts! (not (is-paused)) (err "System is paused"))
        (asserts! (> art-amount u0) (err "Art token amount must be greater than zero"))
        (map-insert art-collateral-map 
                    {user: tx-sender} 
                    {art-tokens: (+ art-amount (default-to u0 (get art-tokens (map-get? art-collateral-map {user: tx-sender}))))})
        (ok art-amount)))

(define-public (take-loan (amount uint))
    (begin
        (asserts! (not (is-paused)) (err "System is paused"))
        (asserts! (> amount u0) (err "Loan amount must be greater than zero"))
        (asserts! (is-collateral-sufficient tx-sender amount) (err "Insufficient collateral"))
        (map-set loan-balance
                 {user: tx-sender}
                 {balance: (+ amount (default-to u0 (get balance (map-get? loan-balance {user: tx-sender}))))})
        (ok amount)))

(define-public (repay-loan (amount uint))
    (begin
        (asserts! (not (is-paused)) (err "System is paused"))
        (asserts! (> amount u0) (err "Repayment amount must be greater than zero"))
        (let ((balance (get-loan-balance tx-sender)))
            (asserts! (>= balance amount) (err "Repayment amount exceeds loan balance"))
            (map-set loan-balance {user: tx-sender} {balance: (- balance amount)})
            (let ((art-price (unwrap-panic (get-price))))
                (let ((collateral-to-unlock (/ amount art-price)))
                    (map-set art-collateral-map
                             {user: tx-sender}
                             {art-tokens: (- (get-art-collateral tx-sender) collateral-to-unlock)})
                    (ok collateral-to-unlock))))))

(define-public (liquidate (user principal))
    (begin
        (asserts! (not (is-paused)) (err "System is paused"))
        (let ((collateral (get-art-collateral user))
              (balance (get-loan-balance user))
              (art-price (unwrap-panic (get-price)))
              (min-ratio (var-get min-ltv-ratio)))
            (asserts! (< (* collateral art-price) (* balance (/ min-ratio u100))) 
                     (err "Position is not under-collateralized"))
            (map-delete art-collateral-map {user: user})
            (map-delete loan-balance {user: user})
            (ok true))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          ADMIN FUNCTIONS                     ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (adjust-ltv-ratio (new-ratio uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err "Unauthorized"))
        (asserts! (> new-ratio u100) (err "LTV ratio must be greater than 100%"))
        (var-set min-ltv-ratio new-ratio)
        (ok new-ratio)))

(define-public (pause-system)
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err "Unauthorized"))
        (var-set system-paused true)
        (ok true)))

(define-public (unpause-system)
    (begin
        (asserts! (is-eq tx-sender contract-owner) (err "Unauthorized"))
        (var-set system-paused false)
        (ok true)))

(define-public (withdraw-art-collateral (art-amount uint))
    (begin
        (asserts! (not (is-paused)) (err "System is paused"))
        (asserts! (> art-amount u0) (err "Art token amount must be greater than zero"))
        (let ((collateral (get-art-collateral tx-sender))
              (balance (get-loan-balance tx-sender))
              (art-price (unwrap-panic (get-price)))
              (min-collateral (* balance (/ (var-get min-ltv-ratio) u100))))
            (asserts! (> collateral min-collateral) (err "Not enough excess collateral"))
            (let ((withdrawable (- collateral min-collateral)))
                (asserts! (>= withdrawable art-amount) (err "Requested amount exceeds excess collateral"))
                (map-set art-collateral-map
                         {user: tx-sender}
                         {art-tokens: (- collateral art-amount)})
                (ok art-amount)))))

(define-public (claim-fees)
    (begin
        (asserts! (not (is-paused)) (err "System is paused"))
        (let ((earned (default-to u0 (get earned (map-get? accrued-fees {user: tx-sender})))))
            (asserts! (> earned u0) (err "No fees to claim"))
            (map-set accrued-fees {user: tx-sender} {earned: u0})
            (ok earned))))
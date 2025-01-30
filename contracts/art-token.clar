;; art-token-lending-protocol


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          CONSTANTS                           ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; (define-constant min-ltv-ratio u150) 
(define-data-var min-ltv-ratio uint u150) ;; Dynamically adjustable


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          DATA STORAGE                        ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-map art-collateral-map
    {user: principal}      
    {art-tokens: uint})           

(define-map loan-balance
    {user: principal}      
    {balance: uint})    

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          READ-ONLY FUNCTIONS                 ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Get the collateral (Art Tokens) locked by a specific user
(define-read-only (get-art-collateral (user principal))
    (default-to u0 (get art-tokens (map-get? art-collateral-map {user: user}))))

;; Get the loan balance of a specific user
(define-read-only (get-loan-balance (user principal))
    (default-to u0 (get balance (map-get? loan-balance {user: user}))))

;; Fetch the current Art Token price from the oracle
(define-read-only (get-art-token-price)
    ;; Replace `.price-oracle` and `get-price` with the actual oracle contract and function
    (contract-call? .price-oracle get-price))

;; Calculate the USD value of a given Art Token amount
(define-read-only (calculate-collateral-value (art-amount uint))
    (let ((art-price (get-art-token-price)))
        (* art-amount art-price)))

;; Check if the user's collateral is sufficient for a specified loan amount
(define-read-only (is-collateral-sufficient (user principal) (loan-amount uint))
    (let ((collateral (get-art-collateral user))
          (art-price (get-art-token-price))
          (min-ratio (var-get min-ltv-ratio)))
        (>= (* collateral art-price) (* loan-amount (/ min-ratio u100)))))

;; Check the loan-to-value ratio of a specific user
(define-read-only (check-ltv-ratio (user principal))
    (let ((collateral (get-art-collateral user))
          (balance (get-loan-balance user))
          (art-price (get-art-token-price)))
        (if (is-eq balance u0)
            (err "No active loans")
            (ok (/ (* collateral art-price) balance)))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          PUBLIC FUNCTIONS                    ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Lock collateral (Art Tokens) to back loans
(define-public (lock-art-collateral (art-amount uint))
    (begin
        (asserts! (> art-amount u0) (err "Art token amount must be greater than zero"))
        (map-insert art-collateral-map 
                    {user: tx-sender} 
                    {art-tokens: (+ art-amount (default-to u0 (get art-tokens (map-get? art-collateral-map {user: tx-sender}))))})
        (ok art-amount)
    ))

;; Take out a loan if sufficient collateral is provided
(define-public (take-loan (amount uint))
    (begin
        (asserts! (> amount u0) (err "Loan amount must be greater than zero"))
        (asserts! (is-collateral-sufficient tx-sender amount) (err "Insufficient collateral"))
        (map-set loan-balance
                 {user: tx-sender}
                 {balance: (+ amount (default-to u0 (get balance (map-get? loan-balance {user: tx-sender}))))})
        (ok amount)
    ))

;; Repay loan and unlock corresponding Art Token collateral
(define-public (repay-loan (amount uint))
    (begin
        (asserts! (> amount u0) (err "Repayment amount must be greater than zero"))
        (let ((balance (get-loan-balance tx-sender)))
            (asserts! (>= balance amount) (err "Repayment amount exceeds loan balance"))
            (map-set loan-balance {user: tx-sender} {balance: (- balance amount)})
            (let ((art-price (get-art-token-price)))
                (let ((collateral-to-unlock (/ amount art-price)))
                    (map-set art-collateral-map
                             {user: tx-sender}
                             {art-tokens: (- (get-art-collateral tx-sender) collateral-to-unlock)})
                    (ok collateral-to-unlock)
                )
            )
        )
    ))

;; Liquidate under-collateralized positions
(define-public (liquidate (user principal))
    (begin
        (let ((collateral (get-art-collateral user))
              (balance (get-loan-balance user))
              (art-price (get-art-token-price))
              (min-ratio (var-get min-ltv-ratio)))
            (asserts! (< (* collateral art-price) (* balance (/ min-ratio u100))) (err "Position is not under-collateralized"))
            (map-delete art-collateral-map {user: user})
            (map-delete loan-balance {user: user})
            (ok true)
        )
    ))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;                          ADMIN FUNCTIONS                     ;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-constant admin tx-sender)
(define-data-var system-paused bool false)

(define-map accrued-fees
    {user: principal}
    {earned: uint})

;; Check if the system is paused
(define-read-only (is-paused)
    (var-get system-paused))

;; Get dynamic minimum LTV ratio
(define-read-only (get-min-ltv-ratio)
    (var-get min-ltv-ratio))

(define-public (adjust-ltv-ratio (new-ratio uint))
    (begin
        (asserts! (is-eq tx-sender admin) (err "Unauthorized"))
        (asserts! (> new-ratio u100) (err "LTV ratio must be greater than 100%"))
        (var-set min-ltv-ratio new-ratio)
        (ok new-ratio)
    ))

;; Admin: Pause system
(define-public (pause-system)
    (begin
        (asserts! (is-eq tx-sender admin) (err "Unauthorized"))
        (var-set system-paused true)
        (ok true)
    ))

;; Admin: Unpause system
(define-public (unpause-system)
    (begin
        (asserts! (is-eq tx-sender admin) (err "Unauthorized"))
        (var-set system-paused false)
        (ok true)
    ))

;; Withdraw excess collateral
(define-public (withdraw-art-collateral (art-amount uint))
    (begin
        (asserts! (not (is-paused)) (err "System is paused"))
        (asserts! (> art-amount u0) (err "Art token amount must be greater than zero"))
        (let ((collateral (get-art-collateral tx-sender))
              (balance (get-loan-balance tx-sender))
              (art-price (get-art-token-price))
              (min-collateral (* balance (/ (var-get min-ltv-ratio) u100))))
            (asserts! (> collateral min-collateral) (err "Not enough excess collateral"))
            (let ((withdrawable (- collateral min-collateral)))
                (asserts! (>= withdrawable art-amount) (err "Requested amount exceeds excess collateral"))
                (map-set art-collateral-map
                         {user: tx-sender}
                         {art-tokens: (- collateral art-amount)})
                (ok art-amount)
            )
        )
    ))

;; Claim accrued fees
(define-public (claim-fees)
    (begin
        (asserts! (not (is-paused)) (err "System is paused"))
        (let ((earned (default-to u0 (get earned (map-get? accrued-fees {user: tx-sender})))))
            (asserts! (> earned u0) (err "No fees to claim"))
            (map-set accrued-fees {user: tx-sender} {earned: u0})
            (ok earned)
        )
    ))
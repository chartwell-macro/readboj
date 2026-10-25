.readboj_databases <- local({
  db <- c(
    "IR01", "IR02", "IR03", "IR04",
    "FM01", "FM02", "FM03", "FM04", "FM05", "FM06", "FM07", "FM08", "FM09",
    "PS01", "PS02",
    "MD01", "MD02", "MD03", "MD04", "MD05", "MD06", "MD07", "MD08", "MD09",
    "MD10", "MD11", "MD12", "MD13", "MD14",
    "LA01", "LA02", "LA03", "LA04", "LA05",
    "BS01", "BS02", "FF", "OB01", "OB02", "CO",
    "PR01", "PR02", "PR03", "PR04", "PF01", "PF02", "BP01", "BIS", "DER", "OT"
  )
  category_en <- c(
    rep("Interest Rates on Deposits and Loans", 4), rep("Financial Markets", 9),
    rep("Payment and Settlement", 2), rep("Money, Deposits and Loans", 19),
    rep("Balance Sheets", 2), "Flow of Funds", rep("Other Bank of Japan Statistics", 2),
    "TANKAN", rep("Prices", 4), rep("Public Finance", 2),
    rep("Balance of Payments and BIS-Related Statistics", 3), "Others"
  )
  name_en <- c(
    "The Basic Discount Rates and Basic Loan Rates",
    "Average Interest Rates Posted at Financial Institutions by Type of Deposit",
    "Average Interest Rates on Time Deposits by Term",
    "Average Contract Interest Rates on Loans and Discounts",
    "Uncollateralized Overnight Call Rate (average)", "Short-term Money Market Rates",
    "Amounts Outstanding in Short-term Money Market", "Amounts Outstanding in the Call Money Market",
    "Issuance, Redemption, and Outstanding of Public and Corporate Bonds",
    "Trading of Interest-bearing Government Bonds by Purchaser",
    "Government Bonds Sales Over the Counter / Counter Sales Ratio", "Foreign Exchange Rates",
    "Effective Exchange Rate", "Other Payment and Settlement Systems", "Basic Figures on Fails",
    "Monetary Base", "Money Stock", "Monetary Survey", "Changes in Money Stock (M2+CDs) and Credit",
    "Currency in Circulation", "Sources of Changes in BOJ Current Account Balances and Market Operations",
    "Reserves", "BOJ Current Account Balances by Sector", "Monetary Base and the Bank of Japan's Transactions",
    "Amounts Outstanding of Deposits by Depositor", "Deposits, Vault Cash, and Loans and Bills Discounted",
    "Deposits, Vault Cash, and Loans and Bills Discounted by Prefecture",
    "Principal Figures of Financial Institutions", "Time Deposits: Amounts Outstanding and New Deposits by Maturity",
    "Loans and Bills Discounted by Sector", "Loans and Discounts by the Bank of Japan",
    "Outstanding of Loans (Others)", "Commitment Lines Extended by Japanese Banks",
    "Senior Loan Officer Opinion Survey on Bank Lending Practices", "Bank of Japan Accounts",
    "Financial Institutions Accounts", "Flow of Funds", "Bank of Japan's Transactions with the Government",
    "Collateral Accepted by the Bank of Japan", "TANKAN", "Corporate Goods Price Index (CGPI)",
    "Services Producer Price Index (SPPI)", "Input-Output Price Index of the Manufacturing Industry by Sector",
    "Final Demand-Intermediate Demand Price Indexes", "Statement of Receipts and Payments of the Treasury Accounts",
    "National Government Debt", "Balance of Payments", "BIS International Banking Statistics in Japan",
    "Regular Derivatives Market Statistics in Japan", "Others"
  )
  name_jp <- c(
    "\u57fa\u6e96\u5272\u5f15\u7387\u304a\u3088\u3073\u57fa\u6e96\u8cb8\u4ed8\u5229\u7387", "\u9810\u91d1\u7a2e\u985e\u5225\u5e97\u982d\u8868\u793a\u91d1\u5229\u306e\u5e73\u5747\u5e74\u5229\u7387\u7b49", "\u5b9a\u671f\u9810\u91d1\u306e\u9810\u5165\u671f\u9593\u5225\u5e73\u5747\u91d1\u5229", "\u8cb8\u51fa\u7d04\u5b9a\u5e73\u5747\u91d1\u5229",
    "\u7121\u62c5\u4fdd\u30b3\u30fc\u30eb\uff2f\uff0f\uff2e\u7269\u30ec\u30fc\u30c8\uff08\u6bce\u55b6\u696d\u65e5\uff09", "\u77ed\u671f\u91d1\u878d\u5e02\u5834\u91d1\u5229", "\u77ed\u671f\u91d1\u878d\u5e02\u5834\u6b8b\u9ad8", "\u30b3\u30fc\u30eb\u5e02\u5834\u6b8b\u9ad8",
    "\u516c\u793e\u50b5\u767a\u884c\u30fb\u511f\u9084\u304a\u3088\u3073\u73fe\u5b58\u984d", "\u516c\u793e\u50b5\u6d88\u5316\u72b6\u6cc1\uff08\u5229\u4ed8\u56fd\u50b5\uff09", "\u56fd\u50b5\u7a93\u53e3\u8ca9\u58f2\u984d\u30fb\u7a93\u53e3\u8ca9\u58f2\u7387", "\u5916\u56fd\u70ba\u66ff\u5e02\u6cc1",
    "\u5b9f\u52b9\u70ba\u66ff\u30ec\u30fc\u30c8", "\u5404\u7a2e\u6c7a\u6e08", "\u30d5\u30a7\u30a4\u30eb\u306e\u767a\u751f\u72b6\u6cc1", "\u30de\u30cd\u30bf\u30ea\u30fc\u30d9\u30fc\u30b9", "\u30de\u30cd\u30fc\u30b9\u30c8\u30c3\u30af", "\u30de\u30cd\u30bf\u30ea\u30fc\u30b5\u30fc\u30d9\u30a4",
    "\u30de\u30cd\u30fc\u30b5\u30d7\u30e9\u30a4\uff08M2+CD\uff09\u5897\u6e1b\u3068\u4fe1\u7528\u9762\u306e\u5bfe\u5fdc", "\u901a\u8ca8\u6d41\u901a\u9ad8", "\u65e5\u9280\u5f53\u5ea7\u9810\u91d1\u5897\u6e1b\u8981\u56e0\u3068\u91d1\u878d\u8abf\u7bc0\uff08\u5b9f\u7e3e\uff09", "\u6e96\u5099\u9810\u91d1\u984d",
    "\u696d\u614b\u5225\u306e\u65e5\u9280\u5f53\u5ea7\u9810\u91d1\u6b8b\u9ad8", "\u30de\u30cd\u30bf\u30ea\u30fc\u30d9\u30fc\u30b9\u3068\u65e5\u672c\u9280\u884c\u306e\u53d6\u5f15", "\u9810\u91d1\u8005\u5225\u9810\u91d1", "\u9810\u91d1\u30fb\u73fe\u91d1\u30fb\u8cb8\u51fa\u91d1",
    "\u90fd\u9053\u5e9c\u770c\u5225\u9810\u91d1\u30fb\u73fe\u91d1\u30fb\u8cb8\u51fa\u91d1", "\u8cb8\u51fa\u30fb\u9810\u91d1\u52d5\u5411", "\u5b9a\u671f\u9810\u91d1\u306e\u6b8b\u9ad8\u304a\u3088\u3073\u65b0\u898f\u53d7\u5165\u9ad8", "\u8cb8\u51fa\u5148\u5225\u8cb8\u51fa\u91d1",
    "\u65e5\u672c\u9280\u884c\u8cb8\u51fa", "\u305d\u306e\u4ed6\u8cb8\u51fa\u6b8b\u9ad8", "\u30b3\u30df\u30c3\u30c8\u30e1\u30f3\u30c8\u30e9\u30a4\u30f3\u5951\u7d04\u984d\u3001\u5229\u7528\u984d", "\u4e3b\u8981\u9280\u884c\u8cb8\u51fa\u52d5\u5411\u30a2\u30f3\u30b1\u30fc\u30c8\u8abf\u67fb",
    "\u65e5\u672c\u9280\u884c\u52d8\u5b9a", "\u6c11\u9593\u91d1\u878d\u6a5f\u95a2\u306e\u8cc7\u7523\u30fb\u8ca0\u50b5", "\u8cc7\u91d1\u5faa\u74b0", "\u65e5\u672c\u9280\u884c\u306e\u5bfe\u653f\u5e9c\u53d6\u5f15",
    "\u65e5\u672c\u9280\u884c\u304c\u53d7\u5165\u308c\u3066\u3044\u308b\u62c5\u4fdd\u306e\u6b8b\u9ad8", "\u77ed\u89b3", "\u4f01\u696d\u7269\u4fa1\u6307\u6570", "\u4f01\u696d\u5411\u3051\u30b5\u30fc\u30d3\u30b9\u4fa1\u683c\u6307\u6570",
    "\u88fd\u9020\u696d\u90e8\u9580\u5225\u6295\u5165\u30fb\u7523\u51fa\u7269\u4fa1\u6307\u6570", "\u6700\u7d42\u9700\u8981\u30fb\u4e2d\u9593\u9700\u8981\u7269\u4fa1\u6307\u6570", "\u8ca1\u653f\u8cc7\u91d1\u53ce\u652f", "\u653f\u5e9c\u50b5\u52d9", "\u56fd\u969b\u53ce\u652f\u7d71\u8a08",
    "BIS\u56fd\u969b\u8cc7\u91d1\u53d6\u5f15\u7d71\u8a08\u304a\u3088\u3073\u56fd\u969b\u4e0e\u4fe1\u7d71\u8a08\u306e\u65e5\u672c\u5206\u96c6\u8a08\u7d50\u679c", "\u30c7\u30ea\u30d0\u30c6\u30a3\u30d6\u53d6\u5f15\u306b\u95a2\u3059\u308b\u5b9a\u4f8b\u5e02\u5834\u5831\u544a", "\u305d\u306e\u4ed6"
  )
  data.frame(db, category_en, name_en, name_jp, manual_revision = "2026-02-18",
    stringsAsFactors = FALSE)
})

#' List Bank of Japan API databases
#'
#' Returns the 50 database identifiers in the February 18, 2026 official API
#' manual. The revision column makes the static registry identity explicit.
#'
#' @return A data frame with database code, category and bilingual names.
#' @export
boj_databases <- function() attach_provenance(.readboj_databases, list(
  source = "Bank of Japan Time-Series Data Search API Manual",
  source_url = "https://www.stat-search.boj.or.jp/info/api_manual_en.pdf",
  source_sha256 = "8e289fb77b9e3f80569206d27059eeb3f35e824facff1c339670179aad5ba9cd",
  source_bytes = 857117, source_retrieved_at = "2026-08-02 Australia/Sydney",
  manual_revision = "2026-02-18", complete_declared_surface = TRUE,
  database_count = 50L))

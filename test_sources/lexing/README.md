## Lexer Testing Folder

Every named folder represents a separate test of the Lexer.

Inside every named folder MUST be the following files:

- `source.duro`
  - A Duroscript source file to pass to the lexer. It does strictly need to have valid syntax, testing for illegal conditions is also part of the testing process.
- `tokens.expected`
  - A plain-text file representing the expected output from `Token.create_token_output_file(token_list)`. For example, an integer literal token with a value of 42 would be expected to be represented as `LIT_INTEGER(42)` (see `Token.zig` for details). Every expected token must be separated by either a space or a newline. The exact kind or quantity of spaces and newlines does not affect the test result, but all expected tokens MUST be in the same order as those produced by the lexer. 
  - Warning: char, string, and template-string literal tokens must NOT contain the character `)`, as the tester scans forward for that character to know when the token has ended. This may change in the future

Additionally, a folder may OPTIONALLY include:

- `notices.expected`
  - A plain-text file of space/newline separated notice kinds (see `NoticeManager.KIND`) that represents the expected errors/warnings/hints produced by the lexer. Right now these messages are not programatically tested, but may be included as a means for manual human review of the error-reporting system.

After running the test binary, the following files are produced in the same folder:

- `tokens.produced`
  - A plain-text file of the actual tokens produced by the Lexer. These will generally be on the same line as they were found in the source file. Every token will be separated by either a single space or newline. This file will be automatically tested against `tokens.expected` to pass/fail the test.
- `notices.produced`
  - A plain-text file of the produced notices logged to the NoticeManager (see `NoticeManager.KIND`). These are not strictly in generated order, as the NoticeManager sorts notices first be severity THEN by chronological order within that severity, making automated testing difficult.
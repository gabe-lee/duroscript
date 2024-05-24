pub const ENC = struct {
    // Digits
    pub const _0 = 0x00;
    pub const _1 = 0x01;
    pub const _2 = 0x02;
    pub const _3 = 0x03;
    pub const _4 = 0x04;
    pub const _5 = 0x05;
    pub const _6 = 0x06;
    pub const _7 = 0x07;
    pub const _8 = 0x08;
    pub const _9 = 0x09;
    // Uppercase alpha
    pub const A = 0x0A;
    pub const B = 0x0B;
    pub const C = 0x0C;
    pub const D = 0x0D;
    pub const E = 0x0E;
    pub const F = 0x0F;
    pub const G = 0x10;
    pub const H = 0x11;
    pub const I = 0x12;
    pub const J = 0x13;
    pub const K = 0x14;
    pub const L = 0x15;
    pub const M = 0x16;
    pub const N = 0x17;
    pub const O = 0x18;
    pub const P = 0x19;
    pub const Q = 0x1A;
    pub const R = 0x1B;
    pub const S = 0x1C;
    pub const T = 0x1D;
    pub const U = 0x1E;
    pub const V = 0x1F;
    pub const W = 0x20;
    pub const X = 0x21;
    pub const Y = 0x22;
    pub const Z = 0x23;
    // Lowercase alpha
    pub const a = 0x24;
    pub const b = 0x25;
    pub const c = 0x26;
    pub const d = 0x27;
    pub const e = 0x28;
    pub const f = 0x29;
    pub const g = 0x2A;
    pub const h = 0x2B;
    pub const i = 0x2C;
    pub const j = 0x2D;
    pub const k = 0x2E;
    pub const l = 0x2F;
    pub const m = 0x30;
    pub const n = 0x31;
    pub const o = 0x32;
    pub const p = 0x33;
    pub const q = 0x34;
    pub const r = 0x35;
    pub const s = 0x36;
    pub const t = 0x37;
    pub const u = 0x38;
    pub const v = 0x39;
    pub const w = 0x3A;
    pub const x = 0x3B;
    pub const y = 0x3C;
    pub const z = 0x3D;
    // Underscore
    pub const UNDERSCORE = 0x3E;
    // Operator Symbols
    pub const PLUS = 0x3F;
    pub const MINUS = 0x40;
    pub const ASTERISK = 0x41;
    pub const F_SLASH = 0x42;
    pub const B_SLASH = 0x43;
    pub const CARET = 0x44;
    pub const AMPER = 0x45;
    pub const HASH = 0x46;
    pub const DOLLAR = 0x47;
    pub const EQUALS = 0x48;
    pub const EXCLAIM = 0x49;
    pub const QUESTION = 0x4A;
    pub const PERCENT = 0x4B;
    pub const LESS_THAN = 0x4C;
    pub const MORE_THAN = 0x4D;
    pub const AT_SIGN = 0x4E;
    pub const PIPE = 0x4F;
    pub const TILDE = 0x50;
    pub const PERIOD = 0x51;
    // Punctuation/Delimiters
    pub const L_PAREN = 0x52;
    pub const R_PAREN = 0x53;
    pub const L_CURLY = 0x54;
    pub const R_CURLY = 0x55;
    pub const L_SQUARE = 0x56;
    pub const R_SQUARE = 0x57;
    pub const SNGL_QUOTE = 0x58;
    pub const DUBL_QUOTE = 0x59;
    pub const BACKTICK = 0x5A;
    pub const COLON = 0x5B;
    pub const SEMICOL = 0x5C;
    pub const COMMA = 0x5D;
    // Whitespace
    pub const SPACE = 0x5E;
    pub const NEWLINE = 0x5F;
    // Other
    pub const IGNORE = 0x61;
    pub const ILLEGAL = 0x62;
    // CODE COUNT
    const _COUNT = 0x63;

    // Boundaries
    pub const WHITESPACE_MIN = SPACE;
    pub const WHITESPACE_MAX = NEWLINE;
    pub const ALPHA_MIN = A;
    pub const ALPHA_MAX = z;
    pub const DIGIT_MIN = _0;
    pub const DIGIT_MAX = _1;
    pub const ALPHA_NUM_MIN = _0;
    pub const ALPHA_NUM_MAX = z;
    pub const BINARY_MIN = _0;
    pub const BINARY_MAX = _1;
    pub const OCTAL_MIN = _0;
    pub const OCTAL_MAX = _7;
    pub const HEX_MIN = _0;
    pub const HEX_MAX = F;
    pub const IDENTIFIER_FIRST_MIN = A;
    pub const IDENTIFIER_FIRST_MAX = UNDERSCORE;
    pub const IDENTIFIER_REST_MIN = _0;
    pub const IDENTIFIER_REST_MAX = UNDERSCORE;
    pub const ALPHA_NUM_IDENT_MIN = _0;
    pub const ALPHA_NUM_IDENT_MAX = UNDERSCORE;

    const ASCII_TO_LEXBYTE = [256]u8{
        ILLEGAL, // 000 NUL
        ILLEGAL, // 001 SOH
        ILLEGAL, // 002 STX
        ILLEGAL, // 003 ETX
        ILLEGAL, // 004 EOT
        ILLEGAL, // 005 ENQ
        ILLEGAL, // 006 ACK
        ILLEGAL, // 007 BEL
        ILLEGAL, // 008 BS
        SPACE, // 009 H_TAB
        NEWLINE, // 010 NEWLINE
        ILLEGAL, // 011 V_TAB
        ILLEGAL, // 012 FF
        SPACE, // 013 CR
        ILLEGAL, // 014 SO
        ILLEGAL, // 015 SI
        ILLEGAL, // 016 DLE
        ILLEGAL, // 017 DC1
        ILLEGAL, // 018 DC2
        ILLEGAL, // 019 DC3
        ILLEGAL, // 020 DC4
        ILLEGAL, // 021 NAK
        ILLEGAL, // 022 SYN
        ILLEGAL, // 023 ETB
        ILLEGAL, // 024 CAN
        ILLEGAL, // 025 EM
        ILLEGAL, // 026 SUB
        ILLEGAL, // 027 ESC
        ILLEGAL, // 028 FS
        ILLEGAL, // 029 GS
        ILLEGAL, // 030 RS
        ILLEGAL, // 031 US
        SPACE, // 032 SPACE
        EXCLAIM, // 033 EXCLAIM
        DUBL_QUOTE, // 034 DUBL_QUOTE
        HASH, // 035 HASH
        DOLLAR, // 036 DOLLAR
        PERCENT, // 037 PERCENT
        AMPER, // 038 AMPER
        SNGL_QUOTE, // 039 SNGL_QUOTE
        L_PAREN, // 040 L_PAREN
        R_PAREN, // 041 R_PAREN
        ASTERISK, // 042 ASTERISK
        PLUS, // 043 PLUS
        COMMA, // 044 COMMA
        MINUS, // 045 MINUS
        PERIOD, // 046 DOT
        F_SLASH, // 047 F_SLASH
        _0, // 048 0
        _1, // 049 1
        _2, // 050 2
        _3, // 051 3
        _4, // 052 4
        _5, // 053 5
        _6, // 054 6
        _7, // 055 7
        _8, // 056 8
        _9, // 057 9
        COLON, // 058 COLON
        SEMICOL, // 059 SEMICOL
        LESS_THAN, // 060 LESS_THAN
        EQUALS, // 061 EQUALS
        MORE_THAN, // 062 MORE_THAN
        QUESTION, // 063 QUESTION
        AT_SIGN, // 064 AT_SIGN
        A, // 065 A
        B, // 066 B
        C, // 067 C
        D, // 068 D
        E, // 069 E
        F, // 070 F
        G, // 071 G
        H, // 072 H
        I, // 073 I
        J, // 074 J
        K, // 075 K
        L, // 076 L
        M, // 077 M
        N, // 078 N
        O, // 079 O
        P, // 080 P
        Q, // 081 Q
        R, // 082 R
        S, // 083 S
        T, // 084 T
        U, // 085 U
        V, // 086 V
        W, // 087 W
        X, // 088 X
        Y, // 089 Y
        Z, // 090 Z
        L_SQUARE, // 091 L_SQUARE
        B_SLASH, // 092 B_SLASH
        R_SQUARE, // 093 R_SQUARE
        CARET, // 094 CARET
        UNDERSCORE, // 095 UNDERSCORE
        BACKTICK, // 096 BACKTICK
        a, // 097 a
        b, // 098 b
        c, // 099 c
        d, // 100 d
        e, // 101 e
        f, // 102 f
        g, // 103 g
        h, // 104 h
        i, // 105 i
        j, // 106 j
        k, // 107 k
        l, // 108 l
        m, // 109 m
        n, // 110 n
        o, // 111 o
        p, // 112 p
        q, // 113 q
        r, // 114 r
        s, // 115 s
        t, // 116 t
        u, // 117 u
        v, // 118 v
        w, // 119 w
        x, // 120 x
        y, // 121 y
        z, // 122 z
        L_CURLY, // 123 L_CURLY
        PIPE, // 124 PIPE
        R_CURLY, // 125 R_CURLY
        TILDE, // 126 TILDE
        ILLEGAL, // 127 DEL
        ILLEGAL, // 128
        ILLEGAL, // 129
        ILLEGAL, // 130
        ILLEGAL, // 131
        ILLEGAL, // 132
        ILLEGAL, // 133
        ILLEGAL, // 134
        ILLEGAL, // 135
        ILLEGAL, // 136
        ILLEGAL, // 137
        ILLEGAL, // 138
        ILLEGAL, // 139
        ILLEGAL, // 140
        ILLEGAL, // 141
        ILLEGAL, // 142
        ILLEGAL, // 143
        ILLEGAL, // 144
        ILLEGAL, // 145
        ILLEGAL, // 146
        ILLEGAL, // 147
        ILLEGAL, // 148
        ILLEGAL, // 149
        ILLEGAL, // 150
        ILLEGAL, // 151
        ILLEGAL, // 152
        ILLEGAL, // 153
        ILLEGAL, // 154
        ILLEGAL, // 155
        ILLEGAL, // 156
        ILLEGAL, // 157
        ILLEGAL, // 158
        ILLEGAL, // 159
        ILLEGAL, // 160
        ILLEGAL, // 161
        ILLEGAL, // 162
        ILLEGAL, // 163
        ILLEGAL, // 164
        ILLEGAL, // 165
        ILLEGAL, // 166
        ILLEGAL, // 167
        ILLEGAL, // 168
        ILLEGAL, // 169
        ILLEGAL, // 170
        ILLEGAL, // 171
        ILLEGAL, // 172
        ILLEGAL, // 173
        ILLEGAL, // 174
        ILLEGAL, // 175
        ILLEGAL, // 176
        ILLEGAL, // 177
        ILLEGAL, // 178
        ILLEGAL, // 179
        ILLEGAL, // 180
        ILLEGAL, // 181
        ILLEGAL, // 182
        ILLEGAL, // 183
        ILLEGAL, // 184
        ILLEGAL, // 185
        ILLEGAL, // 186
        ILLEGAL, // 187
        ILLEGAL, // 188
        ILLEGAL, // 189
        ILLEGAL, // 190
        ILLEGAL, // 191
        ILLEGAL, // 192
        ILLEGAL, // 193
        ILLEGAL, // 194
        ILLEGAL, // 195
        ILLEGAL, // 196
        ILLEGAL, // 197
        ILLEGAL, // 198
        ILLEGAL, // 199
        ILLEGAL, // 200
        ILLEGAL, // 201
        ILLEGAL, // 202
        ILLEGAL, // 203
        ILLEGAL, // 204
        ILLEGAL, // 205
        ILLEGAL, // 206
        ILLEGAL, // 207
        ILLEGAL, // 208
        ILLEGAL, // 209
        ILLEGAL, // 210
        ILLEGAL, // 211
        ILLEGAL, // 212
        ILLEGAL, // 213
        ILLEGAL, // 214
        ILLEGAL, // 215
        ILLEGAL, // 216
        ILLEGAL, // 217
        ILLEGAL, // 218
        ILLEGAL, // 219
        ILLEGAL, // 220
        ILLEGAL, // 221
        ILLEGAL, // 222
        ILLEGAL, // 223
        ILLEGAL, // 224
        ILLEGAL, // 225
        ILLEGAL, // 226
        ILLEGAL, // 227
        ILLEGAL, // 228
        ILLEGAL, // 229
        ILLEGAL, // 230
        ILLEGAL, // 231
        ILLEGAL, // 232
        ILLEGAL, // 233
        ILLEGAL, // 234
        ILLEGAL, // 235
        ILLEGAL, // 236
        ILLEGAL, // 237
        ILLEGAL, // 238
        ILLEGAL, // 239
        ILLEGAL, // 240
        ILLEGAL, // 241
        ILLEGAL, // 242
        ILLEGAL, // 243
        ILLEGAL, // 244
        ILLEGAL, // 245
        ILLEGAL, // 246
        ILLEGAL, // 247
        ILLEGAL, // 248
        ILLEGAL, // 249
        ILLEGAL, // 250
        ILLEGAL, // 251
        ILLEGAL, // 252
        ILLEGAL, // 253
        ILLEGAL, // 254
        ILLEGAL, // 255
    };

    pub const LEXBYTE_TO_HEX = [_COUNT]u8{
        _0,
        _1,
        _2,
        _3,
        _4,
        _5,
        _6,
        _7,
        _8,
        _9,
        A,
        B,
        C,
        D,
        E,
        F,
        G,
        H,
        I,
        J,
        K,
        L,
        M,
        N,
        O,
        P,
        Q,
        R,
        S,
        T,
        U,
        V,
        W,
        X,
        Y,
        Z,
        A,
        B,
        C,
        D,
        E,
        F,
        G,
        H,
        I,
        J,
        K,
        L,
        M,
        N,
        O,
        P,
        Q,
        R,
        S,
        T,
        U,
        V,
        W,
        X,
        Y,
        Z,
        UNDERSCORE,
        PLUS,
        MINUS,
        ASTERISK,
        F_SLASH,
        B_SLASH,
        CARET,
        AMPER,
        HASH,
        DOLLAR,
        EQUALS,
        EXCLAIM,
        QUESTION,
        PERCENT,
        LESS_THAN,
        MORE_THAN,
        AT_SIGN,
        PIPE,
        TILDE,
        PERIOD,
        L_PAREN,
        R_PAREN,
        L_CURLY,
        R_CURLY,
        L_SQUARE,
        R_SQUARE,
        SNGL_QUOTE,
        DUBL_QUOTE,
        BACKTICK,
        COLON,
        SEMICOL,
        COMMA,
        SPACE,
        NEWLINE,
        IGNORE,
        ILLEGAL,
    };
};

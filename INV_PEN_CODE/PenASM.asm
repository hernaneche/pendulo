;******************************************************************************
;
; Software License Agreement                                         
;                                                                    
; The software supplied herewith by Microchip Technology             
; Incorporated (the "Company") is intended and supplied to you, the  
; Company�s customer, for use solely and exclusively on Microchip    
; products. The software is owned by the Company and/or its supplier,
; and is protected under applicable copyright laws. All rights are   
; reserved. Any use in violation of the foregoing restrictions may   
; subject the user to criminal sanctions under applicable laws, as   
; well as to civil liability for the breach of the terms and         
; conditions of this license.                                        
;                                                                     
; THIS SOFTWARE IS PROVIDED IN AN "AS IS" CONDITION. NO WARRANTIES,  
; WHETHER EXPRESS, IMPLIED OR STATUTORY, INCLUDING, BUT NOT LIMITED  
; TO, IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A       
; PARTICULAR PURPOSE APPLY TO THIS SOFTWARE. THE COMPANY SHALL NOT,  
; IN ANY CIRCUMSTANCES, BE LIABLE FOR SPECIAL, INCIDENTAL OR         
; CONSEQUENTIAL DAMAGES, FOR ANY REASON WHATSOEVER.       
;
;*********************************************************************************
;
; File:		PenASM.asm
; Date:		14 October, 2004		Original code
; Version: 	1.00
;
;*********************************************************************************
	list      p=16f684           ; list directive to define processor
	#include <p16F684.inc>        ; processor specific variable definitions
	errorlevel  -302              ; suppress message 302 from list file

	__CONFIG   _CP_OFF & _CPD_OFF & _BOD_OFF & _MCLRE_ON & _WDT_OFF & _INTRC_OSC_NOCLKOUT & _FCMEN_ON

#DEFINE	WORK_TEMP	20H			;CAN BE 20H OR 80H NEED TO RESERVE BOTH LOCATIONS	
#DEFINE	STATUS_TEMP	21H			;FOR STORING THE TEMP DIRECTORY WHILE IN THE INTERRUPT SERVICE ROUTINE
#DEFINE	EN0			22H			;CURRENT ERROR TERM
#DEFINE	EN1			23H			;PREVIOUS ERROR TERM
#DEFINE	EN2			24H			;TWO ERROR TERMS AGO
#DEFINE	EN3			25H			;THREE ERROR TERMS AGO
#DEFINE	KP			26H			;PROPORTIONAL CONSTANT
#DEFINE	KI			27H			;INTERGRAL CONSTANT
#DEFINE	KD			28H			;DERIVATIVE CONSTANT
#DEFINE	AARGB0		29H			;USED IN THE MULTIPLY ROUTINE 8 BIT MULTIPLICAND AND HIGH BYTE OF 16 BIT RESULT
#DEFINE	AARGB1		2AH			;LOWER BYTE OF THE 16 BIT RESULT FOR THE MULTIPY ROUTINE
#DEFINE	BARGB0		2BH			;8 BIT MULTIPLIER FOR THE MULTIPLY ROUTINE
#DEFINE	SIGN		2CH			;ONLY USED IN THE MULTIPLY ROUTINE
#DEFINE	TEMPB3		2DH			;ONLY USED IN THE MULTIPLY ROUTINE
#DEFINE	LOOPCOUNT	2EH			;ONLY USED IN THE MULTIPLY ROUTINE
#DEFINE	INT_TERM_H	2FH			;INTEGRAL TERM UPPER BYTE
#DEFINE	INT_TERM_L	30H			;INTEGRAL TERM LOWER BYTE
#DEFINE	DER_TERM_H	31H			;DERIVATIVE TERM HIGH BYTE
#DEFINE	DER_TERM_L	32H			;DERIVATIVE TERM LOW BYTE
#DEFINE	TEMP		33H			;TEMP REGISTER ONLY USED IN THE INTERRUPT ROUTINE
#DEFINE	TEMP2		34H			;ONLY USED OUTSIDE OF THE INTERRUPT 
#DEFINE	DO_PID		35H			;STATUS FLAG SET IN THE INTERRUPT ROUTINE AND CLEARED AT THE END OF THE PID LOOP
								;WHEN SET THE PID LOOP NEEDS TO BE RUN

	
BANK1	MACRO
	BSF		STATUS, RP0			;MACRO TO SELECT BANK 1
	ENDM	

BANK0	MACRO
	BCF		STATUS, RP0			;MACRO TO SELECT BANK 0
	ENDM

DELAY	MACRO	A
	MOVLW	A					;MACRO USED FOR GENERATING A DELAY
	MOVWF	TEMP2
	CALL	DELAY_SUB
	ENDM	

	ORG     0x000             	;RESET VECTOR
	BANK0
	GOTO    INIT        		;GO TO BEGINING OF THE PROGRAM
	
;INTERRUPT SERVICE ROUTINE
	;INTERRUPT WILL RUN THE PID LOOP BASED OFF THE TMR0 INTERRUPT
	;IT IS DESIRED THAT THIS LOOP WILL HAPPEN AT 256Hz OR 3.9mSECONDS
	;WITH THE 8MHz OSCILLATOR WE HAVE AN INSTRUCTION TIME OF 0.5uSECONDS
	;WITH THE TMR0 PRESCALER SET TO 32 TMR0 WILL INCREMENT EVERY 16uSECONDS
	;THE TMR0 INTERRUPT FLAG IS SET EVERY TIME THE COUNTER OVERFLOWS
	;SO WE NEED TO PRELOAD THE TMR0 TO 256 - (3.9mSECONDS/16uSENCONDS) = 11
	ORG     0x004				;INTERRUPT VECTOR LOCATION
	MOVWF	WORK_TEMP			;SAVE MY WORKING DIRECTORY, CAN BE BANK 0 OR 1
	MOVF	STATUS, W			;GET A COPY OF MY STATUS REGISTER
	BANK0
	MOVWF	STATUS_TEMP			;STORE THE IN BANK 0
	MOVLW	.11					;RESET THE TMRO INTERRUPT TO HAPPEN IN 3.9mSECONDS 256Hz
								;
	MOVWF	TMR0	
	BSF		PORTA, 4
	BSF		ADCON0,	GO			;DO AN A/D CONVERSION

AD_CONVERSION
	BTFSC	ADCON0, NOT_DONE
	GOTO	AD_CONVERSION		;STAY IN THIS LOOP UNTIL THE A/D CONVERSION IS FINISHED

	MOVF	ADRESH,	W			;TAKE THE A/D'S 8 MSB AND SET THEM AS THE CURRENT ERROR
	MOVWF	EN0
	MOVLW	B'10000000'			;SUBTRACK THE DC OFFSET (128 DECIMAL) FROM EN0
								;2'S COMPLEMENT OF 128 DECIMAL IS B'10000000' OR -128 DECIMAL
	ADDWF	EN0,	F			;EN0 IS NOW SIGNED AN EN0=127 CORRESPONDS TO AN ANGLE OF 30 DEGREES
								;EN0=-128 EQUALS AN ANGLE OF -30 DEGREES
	INCF	DO_PID,	F			;ENABLE THE PID UPDATE
	
	BTFSC	EN0,	7
	GOTO	CHECK_NEG
CHECK_POS						;TEST TO SEE IF THE ERROR VALUE IS TOO HIGH TO TRY AND COMPENSATE FOR
;	MOVLW	B'11101011'			;5 DEGREES = 21 DECIMAL = B'00010101' 2'S COMP IS B'11101011'
;	MOVLW	B'11010110'			;10 DEGREES = 42 DECIMAL = B'00101010' 2'S COMP IS B'11010110'
	MOVLW	B'10101100'			;20 DEGREES = 84 DECIMAL = B'01010100' 2'S COMP IS B'10101100'
	ADDWF	EN0,	W			;	
	MOVWF	TEMP
	BTFSS	TEMP,	7			;IF BIT 7 IS SET THE RESULT OF THE ADD IS NEGATIVE WHICH IS OK
	GOTO	STOP_CONTROL		;POSITIVE ERROR IS TOO BIG
	GOTO	LEAVE_INT			;POSITIVE ERROR IS OK
CHECK_NEG						;TEST TO SEE IF THE ERROR VALUE IS TOO LOW TO TRY AND COMPENSATE FOR
;	MOVLW	B'00010101'			;-5 DEGREES = -21 DECIMAL = B'11101011' 2'S COMP IS B'00010101'
;	MOVLW	B'00101010'			;-10 DEGREES = -42 DECIMAL = B'11101011' 2'S COMP IS B'00101010'
	MOVLW	B'01010100'			;-20 DEGREES = -84 DECIMAL = B'10101100' 2'S COMP IS B'01010100'
	ADDWF	EN0,	W			;	
	MOVWF	TEMP
	BTFSS	TEMP,	7			;IF BIT 7 IS SET THE RESULT OF THE ADD IS NEGATIVE WHICH NOT OK
	GOTO	LEAVE_INT			;POSITIVE ERROR IS OK
STOP_CONTROL
	CLRF	DO_PID				;ERROR IS TOO BIG STOP ALL CONTROL DON'T UPDATE PID CONSTANTS
	CLRF	CCPR1L				;TURN THE PWM OFF
	BCF		CCP1CON, 5
	BCF		CCP1CON, 4
	CLRF	INT_TERM_H			;CLEAR ALL VARIABLES THAT ARE ALREADY SET
	CLRF	INT_TERM_L
	CLRF	EN0
	CLRF	EN1
	CLRF	EN2
	CLRF	EN3
	CLRF	DER_TERM_L
	CLRF	DER_TERM_H
LEAVE_INT
	BCF		INTCON, T0IF		;CLEAR MY INTERRUPT FLAG
	MOVF	STATUS_TEMP, W		;REPLACE THE STATUS REGISTER
	MOVWF	STATUS				;
	MOVF	WORK_TEMP, W		;REPLACE THE WORKING REGISTER
	BCF		INTCON, T0IF		;CLEAR THE TMR0 INTERRUPT FLAG
	RETFIE						;RETURN FROM INTERRUPT

INIT
	BANK0
	CLRF	PORTA
	CLRF	PORTC
	MOVLW	B'00000001'			;A/D LEFT JUSTIFIED, VDD IS VOLTAGE REFERENCE
	MOVWF	ADCON0				;A/D IS ON
	CLRF	CCPR1L				;SET PWM DUTY CYCLE TO ZERO
	BCF		CCPR1H, 5			;
	BCF		CCPR1H, 4			;
	MOVLW	B'01001100'			;FULL BRIDGE FORWARD
	MOVWF	CCP1CON				;PWM MODE P1A, P1B, P1C AND P1D ACTIVE HIGH
	CLRF	ECCPAS				;DISABLE THE AUTO-SHUTDOWN 
	MOVLW	B'00000100'			;TMR2 POSTSCALER=1 TMR2 ON PRESCALER=1
	MOVWF	T2CON
	MOVLW	B'00000111'			;COMPARATORS ARE OFF
	MOVWF	CMCON0
	BANK1
	MOVLW	B'00101101'			;SET RA4 AND RA1 AS OUTPUTS	
	MOVWF	TRISA
	MOVLW	B'00000011'			;SET RC0 AND RC1 AS INPUTS	
	MOVWF	TRISC
	MOVLW	B'11000100'			;PORTA PULL-UP DISABLED, INT EDGE, TOCS INT, T0SE LOW-HIGH
	MOVWF	OPTION_REG			;PSA TMR0, RATE 1:32
	MOVLW	B'10100000'			;ENABLE GLOBAL INTERRUPTS
	MOVWF	INTCON				;ENABLE TMR0 INTERRPUT
	CLRF	PIE1				;DISABLE ALL PERIPHERAL INTERRUPTS
	CLRF	PCON				;DISABLE ULPWUE AND SBODEN
	MOVLW	B'01111111'			;SELECT 8MHz
	MOVWF	OSCCON
	CLRF	IOCA				;DISABLE ALL INTERRUPT ON CHANGE FOR PORT A
	MOVLW	B'00110101'			;4 ANALOG INPUTS AN0,AN2,AN4 AND AN5
	MOVWF	ANSEL
	MOVLW	B'01010000'			;SELECT A/D CONVERSION CLOCK FOSC/16
	MOVWF	ADCON1				;CONVERSION TIME IS 2uSECS
	MOVWF	B'00111111'			;SETS THE PWM FREQ TO 32kHz IF TRM2 PS=1
	MOVWF	PR2

	BANK0
	CLRF	INT_TERM_H			;CLEAR THE INTEGRAL TERM AND RESET ALL PREVIOUS ERRORS
	CLRF	INT_TERM_L
	CLRF	EN0
	CLRF	EN1
	CLRF	EN2
	CLRF	EN3
READ_CONSTANTS					;USING THE 10 BIT A/D IGNORE ADRESHL GIVING AN 8  BIT a/d
	MOVLW	B'00010001'			;SELECT AN4(KI)LEFT JUSTIFIED 
	MOVWF	ADCON0	
	DELAY	.40					;WAIT A MINIMUM OF 20 uSECONDS BEFORE STARTING AN A/D CONVERSION
	BSF		ADCON0, GO			;START THE CONVERSION
WAIT_FOR_KI	
	BTFSC	ADCON0, NOT_DONE	
	GOTO	WAIT_FOR_KI
	MOVF	ADRESH,	W
	MOVWF	KI					;TAKE THE 8BIT RESULT AND SAVE IT IGNORE THE 2 LSB
	RRF		KI,		F			;NEED TO CONVERT KI INTO A SIGNED MULTIPLIER
	BCF		KI,		7			;MAKE SURE ITS A POSITIVE NUMBER
	MOVLW	B'00010101'			;SELECT AN5(KD)LEFT JUSTIFIED 
	MOVWF	ADCON0	
	DELAY	.40					;WAIT A MINIMUM OF 20 uSECONDS BEFORE STARTING AN A/D CONVERSION
	BSF		ADCON0, GO			;START THE CONVERSION
WAIT_FOR_KD	
	BTFSC	ADCON0, NOT_DONE	
	GOTO	WAIT_FOR_KD
	MOVF	ADRESH,	W
	MOVWF	KD					;TAKE THE 8BIT RESULT AND SAVE IT IGNORE THE 2 LSB
	RRF		KD,		F			;NEED TO CONVERT KD INTO A SIGNED MULTIPLIER
	BCF		KD,		7			;MAKE SURE ITS A POSITIVE NUMBER
	MOVLW	B'00001001'			;SELECT AN2(KP)LEFT JUSTIFIED 
	MOVWF	ADCON0	
	DELAY	.40					;WAIT A MINIMUM OF 20 uSECONDS BEFORE STARTING AN A/D CONVERSION
	BSF		ADCON0, GO			;START THE CONVERSION
WAIT_FOR_KP	
	BTFSC	ADCON0, NOT_DONE	
	GOTO	WAIT_FOR_KP
	MOVF	ADRESH,	W
	MOVWF	KP					;TAKE THE 8BIT RESULT AND SAVE IT IGNORE THE 2 LSB
	RRF		KP,		F			;NEED TO CONVERT KP INTO A SIGNED MULTIPLIER
	BCF		KP,		7			;MAKE SURE ITS A POSITIVE NUMBER

	MOVLW	B'00000001'			;DONE READING THE CONSTANTS SET THE A/D UP FOR 
	MOVWF	ADCON0				;AN0(THE ANGLE POTENTIOMETER)

MAIN
	MOVF	DO_PID,	W			;TEST TO SEE IF A PID TERMS NEED TO BE UPDATED
	BTFSC	STATUS,	Z
	GOTO	MAIN				;DO_PID IS ZERO WAIT FOR IT TO CHANGE

PID_INT							;CALCULATE THE INTERGRAL TERM
								;INTEGRAL TERM IS KI*TS*[SUM(EN0)]
								;MULTIPLY EN0 BY KI AND THEN DIVIDE BY FS
								;THE MULTIPLY NEEDS TO BE DONE FIRST SO YOU DON'T LOOSE RESULUTION
								;SUM RESULT INTO THE INT_TERM
	BTFSC	INT_TERM_H,	7		;CHECK IF THE INTEGRAL TERM IS POSITIVE OR NEGATIVE
	GOTO	SUME_NEG
SUME_POS
	BTFSS	EN0, 7				;INTEGRAL TERM IS POSITIVE CHECK SIGN OF THE ERROR TERM
	GOTO	CHECK_2_BIG			;ERROR TERM IS ALSO POSITIVE, CHECK IF RESULT WILL BE TOO BIG
ADD_INT_TERM	
	MOVF	EN0,	W
	MOVWF	AARGB0				;MOVE EN0 TO THE MULTIPLICAND
	MOVF	KI,		W
	MOVWF	BARGB0				;MOVE KI TO THE MULTIPLIER
	CALL	FXM0808S			;CALL THE MULTIPLY SUBROUTINE 16 BIT RESULT IS IN AARGB0 MSB
								;AND AARGB1 LSB
	SWAPF	AARGB1, F			;DIVIDE THE RESULT BY 16 (COMBINATION OF A SCALING FACTOR AND A MULTIPLY BY TS)
	MOVLW	0FH					;
	ANDWF	AARGB1, F			;SET UPPER NIBBLE OF AARGB1 = TO LOWER NIBBLE
	BTFSC	AARGB0, 0			;OF AARGB0
	BSF		AARGB1, 4
	BTFSC	AARGB0, 1
	BSF		AARGB1, 5
	BTFSC	AARGB0, 2
	BSF		AARGB1, 6
	BTFSC	AARGB0, 3
	BSF		AARGB1, 7
	SWAPF	AARGB0, F			
	MOVLW	0FH					;SET UPPER NIBBLE TO 0 OR F TO KEEP PROPER SIGN
	ANDWF	AARGB0,	F
	MOVLW	0F0H
	BTFSC	AARGB0 ,3			;OLD SIGN BIT
	ADDWF	AARGB0,	F
	MOVF	AARGB1,	W			;
	ADDWF	INT_TERM_L,	F		;ADD THE LOWER BYTES TOGETHER
	BTFSC	STATUS, C			;ADD THE CARRY IF ANY
	INCF	INT_TERM_H,	F
	MOVF	AARGB0,	W			;ADD THE UPPER BYTES TOGETHER
	ADDWF	INT_TERM_H,	F		;
	GOTO	PID_DIF
SUME_NEG						;CURRENT INTEGRAL TERM IS NEGATIVE
	BTFSS	EN0,	7
	GOTO	ADD_INT_TERM		;SUME WILL GET CLOSER TO ZERO
	MOVLW	B'00010100'			;20 DECIMAL = B'00010100'
	ADDWF	INT_TERM_H,	W
	MOVWF	TEMP2
	BTFSS	TEMP2,	7			;IF BIT 7 IS SET THE RESULT IS NEGATIVE  
	GOTO	ADD_INT_TERM		;OK TO ADD THE TERM SUME IS NOT 2 BIG
	GOTO	PID_DIF				;
CHECK_2_BIG
	MOVLW	B'11101100'			;-20 DECIMAL = B'11101100'
	ADDWF	INT_TERM_H,	W
	MOVWF	TEMP2
	BTFSC	TEMP2,	7			;IF BIT 7 IS CLEAR THE RESULT IS POSITIVE  
	GOTO	ADD_INT_TERM		;OK TO ADD THE TERM SUME IS NOT 2 BIG

PID_DIF							;CALCULATE THE DIFFERENTIAL TERM
								;DERIVATIVE TERM CALCULATED USING FOLLOWING EQUATION
								;KD(EN0-EN3)/(KP*X*3*TS)
	MOVF	EN0,	W			;WHERE X IS AN UNKNOW SCALING FACTOR
	MOVWF	AARGB0			
	MOVF	EN3,	W
	SUBWF	AARGB0, F
	MOVF	KD,		W
	MOVWF	BARGB0
	CALL	FXM0808S			;CALL THE MULTIPLY SUBROUTINE 16 BIT RESULT IS IN AARGB0 MSB
								;AND AARGB1 LSB
	SWAPF	AARGB0, F			;DIVIDE BY 16 (PRECALCULATED KP*X*3*TS)
	MOVLW	0F0H				;MASK OFF LOWER NIBBLE
	ANDWF	AARGB0, F			
	SWAPF	AARGB1, F			;GET 4 MSB OF AARGB1 AND ADD THEM TO AARGB0
	MOVLW	0FH					;MACK OFF THE UPPER NIBBLE
	ANDWF	AARGB1, W
	ADDWF	AARGB0, W			;STORE IN WORKING 
	MOVWF	DER_TERM_H			;SET THE UPPER BYTE OF THE RESULT, IGNORE LOWER BYTE 
	BTFSC	DER_TERM_H, 7
	GOTO	TEST_SMALL			;SEE IF THE RESULT IS TOO SMALL
TEST_LARGE	
	MOVLW	B'11101100'			;-20 DECIMAL 
	ADDWF	DER_TERM_H,	W
	BTFSS	STATUS,	C			;IF CARRY IS SET DER_TERM_H IS TOO BIG  
	GOTO	PID_PROP			;THE TERM IS NOT 2 BIG
	MOVLW	B'00010100'			;20 DECIMAL
	MOVWF	DER_TERM_H
	GOTO 	PID_PROP
TEST_SMALL	
	MOVLW	B'00010100'			;20 DECIMAL
	ADDWF	DER_TERM_H,	W
	BTFSC	STATUS,	C			;IF CARRY IS NOT SET DER_TERM_H IS TOO SMALL  
	GOTO	PID_PROP			;THE TERM IS NOT 2 BIG
	MOVLW	B'11101100'			;-20 DECIMAL 
	MOVWF	DER_TERM_H
PID_PROP						;SUM THE TERMS
	MOVF	EN0,	W			;UP TO +/-85
	MOVWF	AARGB0
	MOVF	INT_TERM_H,	W		;UP TO +/-20
	ADDWF	AARGB0,	F
	MOVF	DER_TERM_H, W		;UP TO +/-20
	ADDWF	AARGB0,	F
	MOVF	KP,		W			;MULTIPLY THE SUMMED TERMS BY KP
	MOVWF	BARGB0
	CALL	FXM0808S			;CALL THE MULTIPLY SUBROUTINE 16 BIT RESULT IS IN AARGB0 MSB
								;AND AARGB1 LSB
SET_MOTOR
	BTFSS	AARGB0, 7			;TEST IF ERROR IS NEGATIVE
	GOTO	SET_FWD				;FULL TERM IS NEGATIVE CHANGE MOTOR TO REVERSE
SET_REV
	BSF		CCP1CON, 7
	BSF		CCP1CON, 6
	COMF	AARGB0,	F			;CONVERT TO A POSITIVE NUMBER
	COMF	AARGB1, F			
	INCF	AARGB1,	F
	BTFSC	STATUS, C
	INCF	AARGB0,	F			;
	GOTO 	SET_PWM
SET_FWD
	BCF		CCP1CON, 7
	BSF		CCP1CON, 6
SET_PWM
	MOVLW	B'11110000'			;TEST TO SEE IF RESULT TO TOO LARGE
	ANDWF	AARGB0, W
	BTFSC	STATUS,	Z			;IF ZERO IS SET ITS OK TO MULTIPLY BY 8
	GOTO	SCALE
	MOVLW	3FH					;WHEN MULTIPLIED BY 4 VALUE IS TOO BIG
	MOVWF	CCPR1L				;SET TO MAX SPEED
	GOTO	SHIFT_ERRORS
SCALE							;MULTIPLY BY 4 ROUTINE TO SCALE RESULT TO PROPER MOTOR SPEED
	RLF		AARGB0,	F
	RLF		AARGB0,	F
	BCF		AARGB0, 1
	BCF		AARGB0, 0
	BTFSC	AARGB1, 7
	BSF		AARGB0, 1	
	BTFSC	AARGB1, 6
	BSF		AARGB0, 0	
	MOVF	AARGB0,	W
	MOVWF	CCPR1L				;SET 10 BIT PWM 8MSB
	BCF		CCP1CON,5			;SET 10 BIT PWM 2LSB
	BCF		CCP1CON,4
	BTFSC	AARGB1, 5
	BSF		CCP1CON,5
	BTFSC	AARGB1, 4
	BSF		CCP1CON,4
SHIFT_ERRORS					;CHANGE THE ERROR TERMS
	MOVF	EN2,	W	
	MOVWF	EN3	
	MOVF	EN1,	W
	MOVWF	EN2	
	MOVF	EN0,	W
	MOVWF	EN1	
	CLRF	DO_PID				;CLEAR PID LOOP FLAG
	BCF		PORTA, 4
	GOTO	MAIN

DELAY_SUB
	DECFSZ	TEMP2,	F
	GOTO 	DELAY_SUB
	RETURN
	
		
;8x8 bit signed fixed point multiply 8x8 -> 16
;Input:		8 bit signed fixed point multiplicand in AARGB0
;			8 bit signed fixed point multiplier in BARGB0
;Result:	AARG
;Max Timing	12+69+2=83 clks	B>0
;			17+69+2=88 clks B<0
;Min Timing	12+46=59 clks
;			6 clks			A=0
FXM0808S	
	CLRF	AARGB1				;CLEAR PARTIAL PRODUCT
	CLRF	SIGN
	MOVF	AARGB0,	W
	BTFSC	STATUS, Z
	RETLW	00H
	
	XORWF	BARGB0,	W
	MOVWF	TEMPB3
	BTFSC	TEMPB3, 7
	COMF	SIGN, F

	BTFSS	BARGB0, 7
	GOTO	M0808SOK
	COMF	BARGB0,	F			;MAKE MULTIPLIER BARG > 0
	INCF	BARGB0,F
	COMF	AARGB0,F
	INCF	AARGB0,F

	BTFSC	BARGB0, 7
	GOTO	M0808SX
M0808SOK

SMUL0808L
	MOVLW	07H
	MOVWF	LOOPCOUNT
	MOVF	AARGB0, W
LOOPSM0808A
	RRF		BARGB0,	F
	BTFSC	STATUS,	C	
	GOTO	LSM0808NA
	DECFSZ	LOOPCOUNT,	F
	GOTO	LOOPSM0808A

	CLRF	AARGB0
	RETLW	00H
LOOPSM0808
	RRF		BARGB0,	F
	BTFSC	STATUS,	C
	ADDWF	AARGB0,	F
LSM0808NA
	RLF		SIGN, 	F	
	RRF		AARGB0,	F
	RRF		AARGB1,	F
	DECFSZ	LOOPCOUNT,	F
	GOTO	LOOPSM0808
	RLF		SIGN,	F
	RRF		AARGB0,	F
	RRF		AARGB1,	F
	RETLW	00H
M0808SX
	CLRF	AARGB1
	RLF		SIGN, W
	RRF		AARGB0,F
	RRF		AARGB1,F
	RETLW	00H


	END

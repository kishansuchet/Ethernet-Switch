LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_unsigned.ALL;
USE std.textio.ALL;

Entity FCSBlockTop is
port(
clk : 		in std_logic;
inputA :	in std_logic_vector(7 downto 0);
inputB : 	in std_logic_vector(7 downto 0);
inputC : 	in std_logic_vector(7 downto 0);
inputD : 	in std_logic_vector(7 downto 0);
reset : 	in std_logic;
--MAC Learning connections
WportMAC : 	out std_logic_vector(3 downto 0);
src1 : 		out std_logic_vector(47 downto 0);
dst1 : 		out std_logic_vector(47 downto 0);
src2 : 		out std_logic_vector(47 downto 0);
dst2 : 		out std_logic_vector(47 downto 0);
src3 : 		out std_logic_vector(47 downto 0);
dst3 : 		out std_logic_vector(47 downto 0);
src4 : 		out std_logic_vector(47 downto 0);
dst4 : 		out std_logic_vector(47 downto 0);


--Crossbar Connections. 9 bit long, last bit used to signify end of packet.
OutA : 			out std_logic_vector(8 downto 0);
OutB : 			out std_logic_vector(8 downto 0);
OutC : 			out std_logic_vector(8 downto 0);
OutD : 			out std_logic_vector(8 downto 0);
wportCross: 		out std_logic_vector(3 downto 0)


);
end FCSBlockTop;

architecture arch of FCSBlockTop is
--Component assignments --

component fcs_check_parallel
port(
	clk            : IN std_logic;                      -- system clock
	reset          : IN std_logic;                      -- asynchronous reset
	start_of_frame : IN std_logic;                      -- arrival of the first bit.
	end_of_frame   : IN std_logic;                      -- arrival of the first bit in FCS.
	data_in        : IN std_logic_vector(7 DOWNTO 0);   -- serial input data.
	fcs_error      : OUT std_logic                      -- indicates an error.
	);
end component;

component FiFoPacket
	PORT
	(
		clock		: IN STD_LOGIC ;
		data		: IN STD_LOGIC_VECTOR (8 DOWNTO 0);
		rdreq		: IN STD_LOGIC ;
		sclr		: IN STD_LOGIC ;
		wrreq		: IN STD_LOGIC ;
		empty		: OUT STD_LOGIC ;
		full		: OUT STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (8 DOWNTO 0);
		usedw		: OUT STD_LOGIC_VECTOR (10 DOWNTO 0)
	);
end component;

component FiFoErrors
	PORT
	(
		clock		: IN STD_LOGIC ;
		data		: IN STD_LOGIC_VECTOR (0 DOWNTO 0);
		rdreq		: IN STD_LOGIC ;
		sclr		: IN STD_LOGIC ;
		wrreq		: IN STD_LOGIC ;
		empty		: OUT STD_LOGIC ;
		full		: OUT STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (0 DOWNTO 0);
		usedw		: OUT STD_LOGIC_VECTOR (4 DOWNTO 0)
	);
end component;

--Signal assignments.--
--Misc signals--
signal counter : integer;
--Incoming signals.
signal SoF : std_logic_vector(3 downto 0) := (others => '0');		--Start of Frame Temp
signal EoF : std_logic_vector(3 downto 0) := (others => '0');		--End of Frame Temp


--Error handling signals.
signal fcs_error : std_logic_vector(3 downto 0) := (others => '0');	--Input to FCS error fifos.
signal fcs_error_out : std_logic_vector(3 downto 0) := (others => '0');	--Output of FCS error fifos.
signal wreqErr : std_logic_vector(3 downto 0) := (others => '0');	--Write enable signal for err Fifo
signal rreqErr : std_logic_vector(3 downto 0) := (others => '0');	-- Read enable
signal emptyErr : std_logic_vector(3 downto 0) := (others => '0');
signal fullErr : std_logic_vector(3 downto 0) := (others => '0');
signal usedWErr : std_logic_vector(19 downto 0) := (others => '0');	-- number of used words.

--Packet Signals
signal packetDoneFlag : std_logic_vector(3 downto 0) := (others => '0');
signal emptyPack : std_logic_vector(3 downto 0) := (others => '0');
signal fullPack : std_logic_vector(3 downto 0) := (others => '0');
signal wrreqPack : std_logic_vector(3 downto 0) := (others => '0');
signal rdreqPack : std_logic_vector(3 downto 0) := (others => '0');
signal usedWPack : std_logic_vector(43 downto 0) := (others => '0');
signal readDataA : std_logic_vector(8 downto 0);
signal readDataB : std_logic_vector(8 downto 0);
signal readDataC : std_logic_vector(8 downto 0);
signal readDataD : std_logic_vector(8 downto 0);

--Outgoing Singals
--Signals towards MAC Learning
signal MACReadOut1 : std_logic_vector(47 downto 0) := (others => '0');
signal MACReadOut2 : std_logic_vector(47 downto 0) := (others => '0');
signal MACReadOut3 : std_logic_vector(47 downto 0) := (others => '0');
signal MACReadOut4 : std_logic_vector(47 downto 0) := (others => '0');
signal MACActivePort : std_logic_vector(3 downto 0) := (others => '0');

signal MACReadOut1S : std_logic_vector(47 downto 0) := (others => '0');
signal MACReadOut2S : std_logic_vector(47 downto 0) := (others => '0');
signal MACReadOut3S : std_logic_vector(47 downto 0) := (others => '0');
signal MACReadOut4S : std_logic_vector(47 downto 0) := (others => '0');	

--Signals towards Crossbar
signal crossOutA : std_logic_vector(8 downto 0);
signal crossOutB : std_logic_vector(8 downto 0);
signal crossOutC : std_logic_vector(8 downto 0);
signal crossOutD : std_logic_vector(8 downto 0);

begin
wreqErr <= EoF;	--Enable write if the end of frame is written.


--Read data out. Discard if FCS error (read from FCS FiFo) is high.
readOut : process (clk)
begin
	if rising_edge(clk) then
		--Enable error list read if not empty
		rreqErr <= not emptyErr;
		--FCS1
		if(fcs_error_out(0) = '0') then
			rdreqPack(0) <= '1';
			crossOutA <= readDataA;
			if(counter >= 7 AND counter <= 13) then --Dest MAC is from bytes 7 to 13.
				MACReadOut1(8 * counter - 8 downto 1 * counter -8) <= readDataA;
			end if;
			if counter >= 14 AND counter <= 20 then
				MACReadOut1S(8 * counter - 15 downto 1 * counter -15) <= readDataA;
			end if;
		end if;
	end if;
end process;



counterProc : process (clk)
begin
	if rising_edge(clk) then
		counter <= counter + 1;
		if counter = 20 then	--MAC source address ends at byte 20. 
			counter <= 0;
		end if;
	end if;
end process;
--Port Mapping--

--4 FCS modules.
FCS1 : fcs_check_parallel
port map(
	clk => clk,
	reset => reset,
	start_of_frame => SoF(0),
	end_of_frame => EoF(0),
	data_in => inputA,
	fcs_error => fcs_error(0)
	);
FCS2 : fcs_check_parallel
port map(
	clk => clk,
	reset => reset,
	start_of_frame => SoF(1),
	end_of_frame => EoF(1),
	data_in => inputB,
	fcs_error => fcs_error(1)
	);
FCS3 : fcs_check_parallel
port map(
	clk => clk,
	reset => reset,
	start_of_frame => SoF(2),
	end_of_frame => EoF(2),
	data_in => inputC,
	fcs_error => fcs_error(2)
	);
FCS4 : fcs_check_parallel
port map(
	clk => clk,
	reset => reset,
	start_of_frame => SoF(3),
	end_of_frame => EoF(3),
	data_in => inputD,
	fcs_error => fcs_error(3)
	);

--4 FiFoPacket
FiFoPack1 : FiFoPacket
port map(
	clock => clk,
	data(7 downto 0) => inputA,
	data(8) => packetDoneFlag(0),
	rdreq => rdreqPack(0),
	sclr => reset,
	wrreq => wrreqPack(0),
	empty => emptyPack(0),
	full => fullPack(0),
	q => readDataA(8 downto 0),
	usedw => usedwPack(10 downto 0)
	);
FiFoPack2 : FiFoPacket
port map(
	clock => clk,
	data(7 downto 0) => inputB,
	data(8) => packetDoneFlag(0),
	rdreq => rdreqPack(0),
	sclr => reset,
	wrreq => wrreqPack(0),
	empty => emptyPack(0),
	full => fullPack(0),
	q => readDataB(8 downto 0),
	usedw => usedwPack(21 downto 11)
	);
FiFoPack3 : FiFoPacket
port map(
	clock => clk,
	data(7 downto 0) => inputC,
	data(8) => packetDoneFlag(0),
	rdreq => rdreqPack(0),
	sclr => reset,
	wrreq => wrreqPack(0),
	empty => emptyPack(0),
	full => fullPack(0),
	q => readDataC(8 downto 0),
	usedw => usedwPack(32 downto 22)
	);
FiFoPack4 : FiFoPacket
port map(
	clock => clk,
	data(7 downto 0) => inputD,
	data(8) => packetDoneFlag(0),
	rdreq => rdreqPack(0),
	sclr => reset,
	wrreq => wrreqPack(0),
	empty => emptyPack(0),
	full => fullPack(0),
	q => readDataD(8 downto 0),
	usedw => usedwPack(43 downto 33)
	);
--TODO add 3 more after filling out all mapping.
--4 FiFoErr
FiFoErr1 : FiFoErrors
port map(
	clock => clk,
	data(0) => fcs_error(0),
	rdreq => rreqErr(0),
	sclr => reset,
	wrreq => wreqErr(0),
	empty => emptyErr(0),
	full => fullErr(0),
	q(0) => fcs_error_out(0),
	usedw => usedWErr(4 downto 0)
	);
FiFoErr2 : FiFoErrors
port map(
	clock => clk,
	data(0) => fcs_error(0),
	rdreq => rreqErr(0),
	sclr => reset,
	wrreq => wreqErr(0),
	empty => emptyErr(0),
	full => fullErr(0),
	q(0) => fcs_error_out(0),
	usedw => usedWErr(9 downto 5)
	);
FiFoErr3 : FiFoErrors
port map(
	clock => clk,
	data(0) => fcs_error(0),
	rdreq => rreqErr(0),
	sclr => reset,
	wrreq => wreqErr(0),
	empty => emptyErr(0),
	full => fullErr(0),
	q(0) => fcs_error_out(0),
	usedw => usedWErr(14 downto 10)
	);
FiFoErr4 : FiFoErrors
port map(
	clock => clk,
	data(0) => fcs_error(0),
	rdreq => rreqErr(0),
	sclr => reset,
	wrreq => wreqErr(0),
	empty => emptyErr(0),
	full => fullErr(0),
	q(0) => fcs_error_out(0),
	usedw => usedWErr(19 downto 15)
	);
end architecture;


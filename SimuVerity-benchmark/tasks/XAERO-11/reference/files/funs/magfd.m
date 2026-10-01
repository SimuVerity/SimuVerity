function  J=magfd(DATE,ITYPE,ALT,COLAT,ELONG,dgh,agh)
%  MAGFD
%  Function to compute Earths magnetic field
%  and components: X,Y,Z,T for a given latitude
%  and longitude, date and altitude using IGRF13.



% Initialize IGRFYEAR as 2020
COLAT = pi/2-COLAT;
igrfyear=2020;

    CL=zeros(1,13);%----------------------------------------added by Nicola
    SL=zeros(1,13);%----------------------------------------added by Nicola
    P=zeros(1,104);%----------------------------------------added by Nicola
    Q=zeros(1,104);%----------------------------------------added by Nicola
    FN=0;FM=0;RR=0;
    
    T     = DATE - igrfyear;


R     = ALT;
SLAT  = cos(COLAT);
CLAT  = sin(COLAT);
CL(1) = cos(ELONG);
SL(1) = sin(ELONG);
X     = 0.0;
Y     = 0.0;
Z     = 0.0;
CD    = 1.0;
SD    = 0.0;
L     = 1;
M     = 1;
N     = 0;
RE    = 6371.2; % Earth's mean radius
if ITYPE == 1  % CONVERSION FROM GEODETIC TO GEOCENTRIC COORDINATES
    %A2    = 40680925.;  % squared semi major axis
    %B2    = 40408588.;  % squared semi minor axis
    % WGS84
    A2    = 40680631.6;  %6378.137^2;  % squared semi major axis
    B2    = 40408296.0;  %6356.7523142^2;  % squared semi minor axis
    ONE   = A2*CLAT*CLAT;
    TWO   = B2*SLAT*SLAT;
    THREE = ONE + TWO;
    FOUR  = sqrt(THREE);
    R     = sqrt(ALT*(ALT + 2.0*FOUR) + (A2*ONE + B2*TWO)/THREE);
    CD    = (ALT + FOUR)/R;
    SD    = (A2 - B2)/FOUR*SLAT*CLAT/R;
    ONE   = SLAT;
    SLAT  = SLAT*CD - CLAT*SD;
    CLAT  = CLAT*CD +  ONE*SD;
end
% if geocentric coordinates desired then only need to define the following
RATIO = RE/R;
%
%     COMPUTATION OF SCHMIDT QUASI-NORMAL COEFFICIENTS  P AND X(=Q)
%
P(1)  = 2.0*SLAT;
P(2)  = 2.0*CLAT;
P(3)  = 4.5*SLAT*SLAT - 1.5;
P(4)  = sqrt(27)*CLAT*SLAT;
Q(1)  = -CLAT;
Q(2)  =  SLAT;
Q(3)  = -3.0*CLAT*SLAT;
Q(4)  = sqrt(3)*(SLAT*SLAT - CLAT*CLAT);

NMAX=13; % Max number of harmonic degrees , 13
NPQ=(NMAX*(NMAX+3))/2;
for K=1:NPQ
    if N < M
        M     = 0;
        N     = N + 1;
        RR    = RATIO^(N + 2);
        FN    = N;
    end
    FM    = M;
    if K >= 5 %8,5,5
        if (M-N) == 0 %,7,6,7
            ONE   = sqrt(1.0 - 0.5/FM);
            J     = K - N - 1;
            P(K)  = (1.0 + 1.0/FM)*ONE*CLAT*P(J);
            Q(K)  = ONE*(CLAT*Q(J) + SLAT/FM*P(J));
            SL(M) = SL(M-1)*CL(1) + CL(M-1)*SL(1);
            CL(M) = CL(M-1)*CL(1) - SL(M-1)*SL(1);
        else
            ONE   = sqrt(FN*FN - FM*FM);
            TWO   = sqrt((FN - 1.0)^2 - FM*FM)/ONE;
            THREE = (2.0*FN - 1.0)/ONE;
            I     = K - N;
            J     = K - 2*N + 1;
            P(K)  = (FN + 1.0)*(THREE*SLAT/FN*P(I) - TWO/(FN - 1.0)*P(J));
            Q(K)  = THREE*(SLAT*Q(I) - CLAT/FN*P(I)) - TWO*Q(J);
        end
        %
        %     SYNTHESIS OF X, Y AND Z IN GEOCENTRIC COORDINATES
        %
    end
    ONE   = (agh(L) + dgh(L)*T)*RR;
    
    if M == 0 %10,9,10
        X     = X + ONE*Q(K);
        Z     = Z - ONE*P(K);
        L     = L + 1;
    else
        TWO   = (agh(L+1) + dgh(L+1)*T)*RR;
        THREE = ONE*CL(M) + TWO*SL(M);
        X     = X + THREE*Q(K);
        Z     = Z - THREE*P(K);
        if CLAT > 0 %12,12,11
            Y = Y+(ONE*SL(M)-TWO*CL(M))*FM*P(K)/((FN + 1.0)*CLAT);
        else
            Y = Y + (ONE*SL(M) - TWO*CL(M))*Q(K)*SLAT;
        end
        L     = L + 2;
    end
    M     = M + 1;
end
%     CONVERSION TO COORDINATE SYSTEM SPECIFIED BY ITYPE
ONE   = X;
X     = X*CD +  Z*SD;
Z     = Z*CD - ONE*SD;
%T     = sqrt(X*X + Y*Y + Z*Z);
J=[X,Y,Z]'*1e-9;
%  END

% Plots data from MSF problem simulation.  
% Assumes that simulation time is in vector "tout" and 
% plant states are in matrix "xout".

global dist NREJ NREC 

N = NREJ+NREC;

for i=1:N; L.title{i}=['Brine Level in stage ',int2str(i)]; end
for i=1:N; L.xlabel{i}='Minutes'; end
for i=1:N; L.ylabel{i}=['Level,   L',int2str(i),'   (m)']; end

for i=1:N; T.title{i}=['Brine Temperature in stage ',int2str(i)]; end
for i=1:N; T.xlabel{i}='Minutes'; end
for i=1:N; T.ylabel{i}=['Temperature,   TB',int2str(i),'   (C)']; end

FIg1=figure(20);
set(FIg1,'Units','points','CloseRequestFcn','delete([FIg, FIg1]);');

g1=subplot(211); plot(tout,xout(:,1));
ylabel(L.ylabel(1));title(L.title(1)); 
set(g1,'position',[0.15 0.581098 0.75 0.343902]);
g2=subplot(212); plot(tout,xout(:,1+N));
xlabel('Minutes');
ylabel(T.ylabel(1));title(T.title(1)); 
set(g2,'position',[0.15 0.11 0.75 0.343902]);

Pos=get(gcf,'Position');
   
FIg=figure(21);
set(FIg,'Units','points',...
   'CloseRequestFcn','delete([FIg, FIg1]);','MenuBar','none',...
	'Position',[Pos(1:2)+[20 -60] 180 40],'Name','Signal Selection',...
   'NumberTitle','off');			

axis('off')
text(0.3,0.8,'Enter Stage Number','FontWeight','bold',...
      'Color','w','HorizontalAlignment','center');

CALLback=['Sig=eval(get(emad,''String'')); figure(FIg1);'...
      'g1=subplot(211);plot(tout,xout(:,Sig));ylabel(L.ylabel(Sig));'...
      'title(L.title(Sig));set(g1,''position'',[0.15 0.581098 0.75 0.343902]);'...
      'g2=subplot(212);plot(tout,xout(:,Sig+N));ylabel(T.ylabel(Sig));'...
      'title(T.title(Sig));xlabel(''Minutes'');'...
      'set(g2,''position'',[0.15 0.11 0.75 0.343902]);figure(FIg)'];
 
 emad=uicontrol('Parent',FIg,'Units','points','Position',[15 5 150 20],...
    'callback',CALLback,'Style','edit');	

return   

local Uc,wa,xc,Kd=bit32.bxor,pairs,type,getmetatable
local Yd,Mc,zc,tc,pd,Gc,yd,wc,hb,Dd;
zc=(getfenv());
hb,pd,Mc=(string.char),(string.byte),(bit32 .bxor);
tc=function(ze,Fd)
    local w_,Ud,F,zd,Bb,Ia,Td,Xd;
    Td,w_={},function(Wd,cc,Qa)
        Td[Wd]=Uc(cc,56775)-Uc(Qa,51897)
        return Td[Wd]
    end;
    Xd=Td[25627]or w_(25627,28511,52131)
    while Xd~=64080 do
        if Xd<49046 then
            if Xd>=38876 then
                if Xd>38876 then
                    Ia='';
                    Bb,Xd,zd,Ud=237,63681,(#ze-1)+237,1
                else
                    Xd,Ia=Td[18080]or w_(18080,116927,4555),Ia..hb(Mc(pd(ze,(F-237)+1),pd(Fd,(F-237)%#Fd+1)))
                end
            else
                Bb=Bb+Ud;
                F=Bb
                if Bb~=Bb then
                    Xd=49046
                else
                    Xd=60325
                end
            end
        elseif Xd>=60325 then
            if Xd<=60325 then
                if(Ud>=0 and Bb>zd)or((Ud<0 or Ud~=Ud)and Bb<zd)then
                    Xd=49046
                else
                    Xd=38876
                end
            else
                F=Bb
                if zd~=zd then
                    Xd=49046
                else
                    Xd=60325
                end
            end
        else
            return Ia
        end
    end
end

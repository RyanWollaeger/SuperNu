!Pure diffusion routine

SUBROUTINE diffusion1(z,g,r,mu,t,E,E0,hyparam,vacnt)

  USE gasgridmod
  USE timestepmod
  USE physconstmod
  USE particlemod
  USE inputparmod
  IMPLICIT NONE
  !
  INTEGER(iknd), INTENT(INOUT) :: z, g, hyparam
  REAL(rknd), INTENT(INOUT) :: r, mu, t, E, E0
  LOGICAL, INTENT(INOUT) :: vacnt
  !
  INTEGER(iknd) :: ig, iig
  REAL(rknd) :: r1, r2
  REAL(rknd) :: denom, denom2
  REAL(rknd) :: ddmct, tau, tcensus, PR, PL, PA
  REAL(rknd), DIMENSION(gas_ng) :: PDFg

  denom = sigmaL(g,z)+sigmaR(g,z)+fcoef(z)*sigmapg(g,z)
  denom = denom+(1.0-EmitProbg(g,z))*(1.0-fcoef(z))*sigmapg(g,z)
  r1 = RAND()
  tau = ABS(LOG(r1)/(lspeed*denom))
  tcensus = time+dt-t
  ddmct = MIN(tau,tcensus)
  E = E*(velno*1.0+velyes*EXP(-ddmct/texp))
  E0 = E0*(velno*1.0+velyes*EXP(-ddmct/texp))
  t = t+ddmct
  !WRITE(*,*) ddmct, tau, tcensus
  !Edep(z) = Edep(z)+E
  IF (ddmct == tau) THEN
     r1 = RAND()
     PR = sigmaR(g,z)/denom
     PL = sigmaL(g,z)/denom
     PA = fcoef(z)*sigmapg(g,z)/denom
     IF (0.0_rknd<=r1 .AND. r1<PL) THEN
        IF (z == 1) THEN
           WRITE(*,*) 'Non-physical left leakage'
           !vacnt = .TRUE.
           !done = .TRUE.
           !Eleft = Eleft+E
        ELSEIF (sigmapg(g,z-1)*drarr(z-1)*(velno*1.0+velyes*texp)>=5.0_rknd) THEN
           z = z-1
        ELSE
           hyparam = 1
           r = rarr(z)
           z = z-1
           r1 = RAND()
           r2 = RAND()
           mu = -MAX(r1,r2)
           mu = (mu+velyes*r/lspeed)/(1.0+velyes*r*mu/lspeed)
           E = E/(1.0-velyes*r*mu/lspeed)
           E0 = E0/(1.0-velyes*r*mu/lspeed)
        ENDIF
     ELSEIF (PL<=r1 .AND. r1<PL+PR) THEN
        IF (z == gas_nr) THEN
           vacnt = .TRUE.
           done = .TRUE.
           r1 = RAND()
           r2 = RAND()
           mu = MAX(r1,r2)
           Eright = Eright+E*(1.0+velyes*rarr(gas_nr+1)*mu/lspeed)
        ELSEIF (sigmapg(g,z+1)*drarr(z+1)*(velno*1.0+velyes*texp)>=5.0_rknd) THEN
           z = z+1
        ELSE
           hyparam = 1
           r = rarr(z+1)
           z = z+1
           r1 = RAND()
           r2 = RAND()
           mu = MAX(r1,r2)
           mu = (mu+velyes*r/lspeed)/(1.0+r*mu/lspeed)
           E = E/(1.0-velyes*r*mu/lspeed)
           E0 = E0/(1.0-velyes*r*mu/lspeed)
        ENDIF
     ELSEIF (PL+PR<=r1 .AND. r1<PL+PR+PA) THEN
        vacnt = .TRUE.
        done = .TRUE.
        Edep(z) = Edep(z)+E
     ELSE
        denom2 = sigmap(z)-Ppick(g)*sigmapg(g,z)
        DO ig = 1, gas_ng
           PDFg(ig) = EmitProbg(ig,z)*sigmap(z)/denom2 
        ENDDO
        PDFg(g)=0.0
        denom2 = 0.0
        r1 = RAND()
        DO ig = 1, gas_ng
           iig = ig
           IF (r1>=denom2.AND.r1<denom2+PDFg(ig)) EXIT
           denom2 = denom2+PDFg(ig)
        ENDDO
        g = iig
        IF (sigmapg(g,z)*drarr(z)*(velno*1.0+velyes*texp)>=5.0_rknd) THEN
           hyparam = 2
        ELSE
           hyparam = 1
           r1 = RAND()
           mu = 1.0-2.0*r1
           r1 = RAND()
           r = (r1*rarr(z+1)**3+(1.0-r1)*rarr(z)**3)**(1.0/3.0)
           mu = (mu+velyes*r/lspeed)/(1.0+velyes*r*mu/lspeed)
           E = E/(1.0-velyes*mu*r/lspeed)
           E0 = E0/(1.0-velyes*mu*r/lspeed)
        ENDIF
     ENDIF
  ELSE
     done = .TRUE.
     numcensus(z)=numcensus(z)+1
     Erad = Erad+E
  ENDIF

END SUBROUTINE diffusion1

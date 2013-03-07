SUBROUTINE xsections

  USE gasgridmod
  USE timestepmod
  USE physconstmod
  IMPLICIT NONE

!##################################################
  !This subroutine computes cross sections (opacities) used in
  !the particle advance phase of the program.  These opacities
  !include the grey Planck, grouped Planck, grouped Rosseland,
  !and DDMC grouped leakage opacities.
!##################################################

  INTEGER :: ir, ig
  REAL*8 :: Um, beta, tt, gg, ggg, eps, bb
  ! Here: left=>toward r=0 and right=>outward

  !Interpolating cell boundary temperatures: loop
  gas_tempb(1)=gas_temp(1)
  !gas_tempb(1) = 1.0
  DO ir = 2, gas_nr
     gas_tempb(ir) = (gas_temp(ir)**4+gas_temp(ir-1)**4)/2.0
     gas_tempb(ir) = gas_tempb(ir)**0.25
  ENDDO
  gas_tempb(gas_nr+1)=gas_temp(gas_nr)

  !Picket fence (Planck):
  ! Picket-fence problem
  gas_ppick(1) = 1.0d0
  gas_ppick(2) = 0.0d0
  DO ig = 3, gas_ng
     gas_ppick(ig) = 0.0
  ENDDO

  !Calculating grey Planck and gouped Planck opacities: loop
  DO ir = 1, gas_nr
     gas_sigmapg(1,ir) = 0.10*gas_rhoarr(ir) !/gas_temp(ir)**3
     gas_sigmapg(2,ir) = 0.10*gas_rhoarr(ir) !/gas_temp(ir)**3
     DO ig = 3, gas_ng
        gas_sigmapg(ig,ir) = 1.0 !/gas_temp(ir)**3
     ENDDO
     gas_sigmap(ir)=0.0
     DO ig = 1, gas_ng
        gas_sigmap(ir) = gas_sigmap(ir)+gas_ppick(ig)*gas_sigmapg(ig,ir)
     ENDDO
     Um = gas_bcoef(ir)*gas_temp(ir)
     beta = 4.0*gas_ur(ir)/Um
     gas_fcoef(ir) = 1.0/(1.0+tsp_alpha*beta*pc_c*tsp_dt*gas_sigmap(ir))
     DO ig = 1, gas_ng
        gas_emitprobg(ig,ir) = gas_ppick(ig)*gas_sigmapg(ig,ir)/gas_sigmap(ir)
     ENDDO
  ENDDO
  
  !Calculating group Rosseland opacities: loop
  DO ir = 1, gas_nr
     gas_sigmargleft(1,ir) = 0.10*gas_rhoarr(ir) !/gas_tempb(ir)**3
     gas_sigmargleft(2,ir) = 0.10*gas_rhoarr(ir) !/gas_tempb(ir)**3
     DO ig = 3, gas_ng
        gas_sigmargleft(ig,ir) = 1.0 !/gas_tempb(ir)**3
     ENDDO
     gas_sigmargright(1,ir) = 0.10*gas_rhoarr(ir) !/gas_tempb(ir+1)**3
     gas_sigmargright(2,ir) = 0.10*gas_rhoarr(ir) !/gas_tempb(ir+1)**3
     DO ig = 3, gas_ng
        gas_sigmargright(ig,ir) = 1.0 !/gas_tempb(ir+1)**3
     ENDDO
  ENDDO

  !Calculating IMC-to-DDMC leakage albedo coefficients (Densmore, 2007): loop
  !These quantities may not need to be stored directly (pending further analysis)
  DO ir = 1, gas_nr
     gg = (3.0*gas_fcoef(ir))**0.5
     eps = (4.0/3.0)*gg/(1.0+0.7104*gg)
     DO ig = 1, gas_ng
        !Calculating for leakage from left
        !tt = gas_sigmargleft(ig,ir)*gas_drarr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp)
        tt = gas_sigmapg(ig,ir)*gas_drarr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp)
        ggg = (gg*tt)**2
        bb = (3.0/4.0)*gas_fcoef(ir)*tt**2+(ggg+(ggg**2)/4.0)**0.5
        gas_ppl(ig,ir) = 0.5*eps*bb/(bb-(3.0/4.0)*eps*tt)
        !Calculating for leakage from right
        !tt = gas_sigmargright(ig,ir)*gas_drarr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp)
        tt = gas_sigmapg(ig,ir)*gas_drarr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp)
        ggg = (gg*tt)**2
        bb = (3.0/4.0)*gas_fcoef(ir)*tt**2+(ggg+(ggg**2)/4.0)**0.5
        gas_ppr(ig,ir) = 0.5*eps*bb/(bb-(3.0/4.0)*eps*tt)
     ENDDO
  ENDDO

  !Calculating DDMC(-to-IMC) leakage opacities (Densmore, 2007, 2012): loop
  DO ir = 1, gas_nr
     DO ig = 1, gas_ng  
        !Computing left-leakage opacities
        IF (ir==1) THEN
           !gas_sigmal(ig,ir)=0.5*gas_ppl(ig,ir)/gas_drarr(ir)
           gas_sigmal(ig,ir)=1.5*gas_ppl(ig,ir)*gas_rarr(ir)**2
           gas_sigmal(ig,ir)=gas_sigmal(ig,ir)/(gas_dr3arr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp))
        ELSEIF(gas_sigmapg(ig,ir-1)*gas_drarr(ir-1)*(gas_velno*1.0+gas_velyes*tsp_texp)<5.0d0) THEN
           !gas_sigmal(ig,ir)=0.5*gas_ppl(ig,ir)/gas_drarr(ir)
           gas_sigmal(ig,ir)=1.5*gas_ppl(ig,ir)*gas_rarr(ir)**2
           gas_sigmal(ig,ir)=gas_sigmal(ig,ir)/(gas_dr3arr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp))
        ELSE
           tt = gas_sigmargleft(ig,ir)*gas_drarr(ir)+gas_sigmargright(ig,ir-1)*gas_drarr(ir-1)
           !gas_sigmal(ig,ir) = 2.0/(3.0*gas_drarr(ir)) 
           gas_sigmal(ig,ir) = (2.0*gas_rarr(ir)**2)/(gas_dr3arr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp**2))
           gas_sigmal(ig,ir) = gas_sigmal(ig,ir)/tt
        ENDIF
        !Computing right-leakage opacities
        IF (ir==gas_nr) THEN
           !gas_sigmar(ig,ir)=0.5*gas_ppr(ig,ir)/gas_drarr(ir)
           gas_sigmar(ig,ir)=1.5*gas_ppr(ig,ir)*gas_rarr(ir+1)**2
           gas_sigmar(ig,ir)=gas_sigmar(ig,ir)/(gas_dr3arr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp))
        ELSEIF(gas_sigmapg(ig,ir+1)*gas_drarr(ir+1)*(gas_velno*1.0+gas_velyes*tsp_texp)<5.0d0) THEN
           !gas_sigmar(ig,ir)=0.5*gas_ppr(ig,ir)/gas_drarr(ir)
           gas_sigmar(ig,ir)=1.5*gas_ppr(ig,ir)*gas_rarr(ir+1)**2
           gas_sigmar(ig,ir)=gas_sigmar(ig,ir)/(gas_dr3arr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp))
        ELSE
           tt = gas_sigmargright(ig,ir)*gas_drarr(ir)+gas_sigmargleft(ig,ir+1)*gas_drarr(ir+1)
           !gas_sigmar(ig,ir) = 2.0/(3.0*gas_drarr(ir))
           gas_sigmar(ig,ir) = (2.0*gas_rarr(ir+1)**2)/(gas_dr3arr(ir)*(gas_velno*1.0+gas_velyes*tsp_texp**2))
           gas_sigmar(ig,ir) = gas_sigmar(ig,ir)/tt
        ENDIF
     ENDDO
  ENDDO
  
END SUBROUTINE xsections
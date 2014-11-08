      module totalsmod
!-- energy conservation check quantities
      real*8 :: tot_eext = 0d0 !time-integrated input energy from external source
      real*8 :: tot_emat = 0d0 !material energy
      real*8 :: tot_erad = 0d0 !census radiation energy
      real*8 :: tot_eleft = 0d0 !left (inward) leaked energy from domain
      real*8 :: tot_eright = 0d0 !right (outward) leaked energy from domain
      real*8 :: tot_evelo = 0d0 !total energy change to rad field from fluid
      real*8 :: tot_eerror = 0d0 !error in integral problem energy
!-- average quantities used for energy check with MPI
      real*8 :: tot_eextav = 0d0
      real*8 :: tot_eveloav = 0d0
!--
      real*8 :: tot_esurf = 0d0
      save
      end module totalsmod

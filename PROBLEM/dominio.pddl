(define (domain movimientos-tierra)
  (:requirements :durative-actions :typing :fluents)
  (:types
    aircraft tractor finger pista-aterrizaje pista-rodaje terminal cargador - object
  )

  (:predicates
    ;; ubicación: aviones pueden estar en pistas o en fingers; tractores en pistas de rodaje o en terminales
    (at-aircraft ?a - aircraft ?loc - (either pista-aterrizaje pista-rodaje finger terminal))
    (at-tractor  ?tr - tractor  ?loc - (either pista-rodaje terminal))

    ;; conexiones: hay pistas que no están conectadas con otras pistas/terminales
    (connected ?p1 - (either pista-aterrizaje pista-rodaje terminal) ?p2 - (either pista-aterrizaje pista-rodaje terminal))

    ;; tractor remolcando un avión
    (attached ?tr - tractor ?a - aircraft)
    (any-attached ?a - aircraft)
    ;; finger pertenece a una terminal (fijo)
    (in ?f - finger ?t - terminal)
    ;; finger libre / ocupado
    (free-finger ?f - finger)
    (occupied-finger ?f - finger)
    ;; cargador en terminal
    (in-cargador ?c - cargador ?t - terminal)
    (free-cargador ?c - cargador)
    (charging ?tr - tractor ?c - cargador)
  )

  ;; FUNCIONES NUMÉRICAS (fluent)
  (:functions
    (distance ?p1 - (either pista-aterrizaje pista-rodaje terminal) ?p2 - (either pista-aterrizaje pista-rodaje terminal))
    (aircraft-speed ?a - aircraft)
    (tractor-speed ?tr - tractor)
    (tractor-speed-remolcando ?tr - tractor)
    (carga-restante ?tr - tractor)        ;; batería actual (unidades)
    (duracion-carga ?tr - tractor)        ;; tiempo que tarda en recargarse completamente
    (numero-recargas)
    (deploy-finger-time)
    (retrieve-finger-time)
  )

  ;; ACCIONES DURATIVAS

  ;; 1) mover avión entre pistas (pista-aterrizaje <-> pista-rodaje). Avión se mueve por sí solo.

  (:durative-action move-aircraft
  :parameters (?a - aircraft ?from - (either pista-aterrizaje pista-rodaje) ?to - (either pista-aterrizaje pista-rodaje))
    :duration (= ?duration (/ (distance ?from ?to) (aircraft-speed ?a)))
    :condition (and
                 (at start (at-aircraft ?a ?from))
                 (at start (connected ?from ?to))
                 (over all (not (any-attached ?a))) ;; no debe estar siendo remolcado por ningún tractor
               )
    :effect (and
              (at start (not (at-aircraft ?a ?from)))
              (at end   (at-aircraft ?a ?to))
            )
  )

  ;; 2) mover tractor vacío entre terminal <-> pista-rodaje. Consume 2 unidades de batería

  (:durative-action move-tractor-empty
    :parameters (?tr - tractor ?from - (either pista-rodaje terminal) ?to - (either pista-rodaje terminal))
    :duration (= ?duration (/ (distance ?from ?to) (tractor-speed ?tr)))
    :condition (and
                 (at start (at-tractor ?tr ?from))
                 (at start (>= (carga-restante ?tr) 2))
                 (at start (connected ?from ?to))
               )
    :effect (and
              (at start (not (at-tractor ?tr ?from)))
              (at end   (at-tractor ?tr ?to))
              (at end   (decrease (carga-restante ?tr) 2))
            )
  )

  ;; 3) remolcar avion: tractor remolca un avión entre pista-rodaje <-> terminal
  ;; duración = 2 * distance / tractor-speed y consume 4 unidades de batería
  (:durative-action tow-aircraft
    :parameters (?tr - tractor ?a - aircraft ?from - (either pista-rodaje terminal) ?to - (either pista-rodaje terminal))
    :duration (= ?duration (* 2 (/ (distance ?from ?to) (tractor-speed ?tr))))
    :condition (and
                 (at start (at-tractor ?tr ?from))
                 (at start (at-aircraft ?a ?from))
                 (at start (>= (carga-restante ?tr) 4))
                 (at start (connected ?from ?to))
               )
    :effect (and
              (at start (attached ?tr ?a))
              (at start (any-attached ?a))
              (at start (not (at-tractor ?tr ?from)))
              (at start (not (at-aircraft ?a ?from)))
              (at end   (not (attached ?tr ?a)))
              (at end   (at-tractor ?tr ?to))
              (at end   (at-aircraft ?a ?to))
              (at end   (not (any-attached ?a)))
              (at end   (decrease (carga-restante ?tr) 4))
            )
  )

  ;; 4) deploy finger: el avión queda aparcado en el finger
  (:durative-action deploy-finger
    :parameters (?a - aircraft ?f - finger ?t - terminal)
    :duration (= ?duration (deploy-finger-time))
    :condition (and
                 (at start (at-aircraft ?a ?t)) ;; el avión está en la terminal
                 (at start (in ?f ?t))
                 (at start (free-finger ?f))
                 (at start (not (exists (?tr - tractor) (attached ?tr ?a)))) ;; no remolcado
               )
    :effect (and
              (at start (not (free-finger ?f)))
              (at start (occupied-finger ?f))
              (at end   (at-aircraft ?a ?f)) ;; representamos avión aparcado en finger como su "ubicación" siendo el finger
              (at end   (not (at-aircraft ?a ?t)))
            )
  )

  ;; 5) retrieve/retract finger (desocupar)

  (:durative-action retrieve-finger
    :parameters (?a - aircraft ?f - finger ?t - terminal)
    :duration (= ?duration (retrieve-finger-time))
    :condition (and
                 (at start (in ?f ?t))
                 (at start (occupied-finger ?f))
                 (at start (at-aircraft ?a ?f))
               )
    :effect (and
              (at end (not (at-aircraft ?a ?f)))
              (at end   (at-aircraft ?a ?t))
              (at end   (not (occupied-finger ?f)))
              (at end   (free-finger ?f))
            )
  )

  ;; 6) recargar tractor en cargador (cargador en terminal)
  ;; solo si carga-restante <= 6; tras recarga carga-restante = 10; incrementa numero-recargas

  (:durative-action recharge
    :parameters (?tr - tractor ?c - cargador ?t - terminal)
    :duration (= ?duration (duracion-carga ?tr))
    :condition (and
                 (at start (at-tractor ?tr ?t))
                 (at start (in-cargador ?c ?t))
                 (at start (free-cargador ?c))
                 (at start (<= (carga-restante ?tr) 6))
               )
    :effect (and
              (at start (not (free-cargador ?c)))
              (at start (charging ?tr ?c))
              (at end   (not (charging ?tr ?c)))
              (at end   (free-cargador ?c))
              (at end   (assign (carga-restante ?tr) 10))
              (at end   (increase (numero-recargas) 1))
            )
  )
)

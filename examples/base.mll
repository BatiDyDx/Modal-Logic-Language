-- Logica Modal
-- use modal -- Importa modulo con definiciones (sujeto a cambios)

set frame = {              -- Indica relacion de transicion entre mundos
  x1 -> {x2,x3,x4},
  x1 -> {x5}, -- ¿Se permite esto? Si se permite ¿actualiza o sobrescribe?
  x2 -> {x2},
  x3 -> {x1},
  x4 -> {x1, x2, x5},
  x6 -> {}
} -- Los vertices se derivan de forma automatica, x1 ... x5

set tag = {                  -- Indica
  x1 -> {}
  x2 -> {}
  x3 -> {p}
  x4 -> {p,q}
}

def Phi = p <-> q  -- Formulas y/o esquemas. Las formulas pueden ser evaluadas
                   -- o usadas a su vez como esquemas de formulas, es decir,
                   -- abstraer una estructura sintactica y luego ser utilizada
                   -- mediante reemplazos a esta

isValid Phi[r and s/p]     -- Reemplazo sintactico, equivalente a "r and s <-> q"

r and q  -- Dos tipos de escritura de proposiciones posible
r &&  q  -- Estilo clasico (&&, ||, !) o estilo literal (and, or, not)
         -- Los operadores -> y <-> se conservan igual para ambas
r and q && t -- Esto es posible, pero no recomendado

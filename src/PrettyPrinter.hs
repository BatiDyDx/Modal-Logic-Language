module PrettyPrinter
  ( pp
  , ppTrace
  ) where

-- import Core
import Common
import Prelude hiding ((<>))
-- import Text.PrettyPrint.ANSI.Leijen
-- import Text.PrettyPrint.HughesPJ
import Prettyprinter
import Data.Maybe (fromMaybe)

type FPrinter = Formula Atom -> FDoc

-- Translation of formula to LaTeX
toLatex :: Formula a -> String
toLatex = undefined

type FDoc = Doc ()
type Color = FDoc -> FDoc
type Coloring a = [(a, Color)]

resetColor :: Color
resetColor = (<> pretty "\ESC[0m")

createColor :: Bool -> String -> Color
createColor bold hex doc = resetColor (pretty ansiColor <> doc)
      where ansiColor = concat ["\ESC[", boldCode, ";", hex, "m"]
            boldCode = if bold then "1" else "0"

red, green, orange, blue, magenta, cyan :: Color
red     = createColor True "91"
green   = createColor True "92"
orange  = createColor True "93"
blue    = createColor True "94"
magenta = createColor True "95"
cyan    = createColor True "96"

defaultColors :: [Color]
defaultColors = cycle colors
  where colors = [orange, blue, magenta, cyan]

assignColors :: [a] -> Coloring a
assignColors = flip zip defaultColors

ppFormula :: FPrinter
ppFormula f = let col = assignColors (atoms f) in pp col f

pp :: Coloring Atom -> FPrinter
pp = pp'
  where
    pp' col  Bottom         = red   $ pretty "F" -- ⊥
    pp' col  Top            = green $ pretty "T" -- ⊤
    pp' col  (Atomic x)     = let c = fromMaybe id (lookup x col) in c (pretty x)
    pp' col  (Not f1)       = ppUnary col (pretty "!") f1 -- ¬
    pp' col  (Square f1)    = ppUnary col (pretty "□") f1
    pp' col  (Diamond f1)   = ppUnary col (pretty "◇") f1
    pp' col  (Or f1 f2)     = let pred f = isBinary f && not (isOr f)
                              in ppBinary col pred (pretty " || ") f1 f2 -- ∨
    pp' col  (And f1 f2)    = let pred f = isImply f || isIff f
                              in ppBinary col pred (pretty " && ") f1 f2  -- ∧
    pp' col  (Imply f1 f2)  = let p1 = parensIf (isImply f1 || isIff f1)
                                  p2 = parensIf (isIff f2)
                              in  p1 (pp' col f1) <> pretty " -> " <> p2 (pp' col f2) -- →
    pp' col  (Iff f1 f2)    = ppBinary col isIff (pretty " <-> ") f1 f2      -- ↔
    ppUnary col sym f = let p = parensIf (isBinary f)
                        in sym <> p (pp' col f)
    ppBinary col pred sym f1 f2 = let p1 = parensIf (pred f1)
                                      p2 = parensIf (pred f2)
                                  in p1 (pp' col f1) <> sym <> p2 (pp' col f2)
-- * operador unario, + operador binario
-- (* (+ x y)) se escribe como * (x + y)
-- Un operador or pone parentesis si su argumento es un operador binario excepto para el or.
-- Indistinto para argumento izquierdo o derecho
-- Un operador and pone parentesis si su argumento es el operador -> o <->.
-- Indistinto para argumento izquierdo o derecho
-- El operador -> asocia a derecha, y por ende lleva parentesis en su argumento
-- izquierdo cuando este es un operador -> o <->. A su argumento derecho solo
-- le pone parentesis cuando es un <->.
-- El operador <-> nunca pone parentesis a sus argumentos ya que es el de menor
-- precedencia.

{------------ Trace Pretty Printing ------------}
ppTrace :: Trace -> FDoc
ppTrace t = let col = assignColors (atoms (getTraceHead t)) in ppTrace' col t
  where
    ppTrace' :: Coloring Atom -> Trace -> FDoc
    ppTrace' col t =  let docs = fmap (ppTrace' col) (getSubtrace t)
                          backtrace = if null docs then emptyDoc
                                                    else (indent 2 (vsep docs)) <> line
                          result = hsep [ pp col (getTraceHead t)
                                        , colon
                                        , space
                                        , ppBool (evalTrace t)
                                        ]
                      in backtrace <> result
    ppBool :: Bool -> FDoc
    ppBool True  = green $ pretty True
    ppBool False = red   $ pretty False

{------------------ Utilities ------------------}
parensIf :: Bool -> FDoc -> FDoc
parensIf True  = parens
parensIf False = id

isTop :: Formula a -> Bool
isTop Top = True
isTop _   = False

isBottom :: Formula a -> Bool
isBottom Bottom = True
isBottom _      = False

isAtomic :: Formula a -> Bool
isAtomic Atomic{} = True
isAtomic _        = False

isNot :: Formula a -> Bool
isNot Not{} = True
isNot _     = False

isSquare :: Formula a -> Bool
isSquare Square{} = True
isSquare _        = False

isDiamond :: Formula a -> Bool
isDiamond Diamond{} = True
isDiamond _         = False

isAnd :: Formula a -> Bool
isAnd And{} = True
isAnd _     = False

isOr :: Formula a -> Bool
isOr Or{} = True
isOr _    = False

isImply :: Formula a -> Bool
isImply Imply{} = True
isImply _       = False

isIff :: Formula a -> Bool
isIff Iff{} = True
isIff _     = False

isConstant :: Formula a -> Bool
isConstant f = any ($ f) [isTop, isBottom, isAtomic]

isUnary :: Formula a -> Bool
isUnary f = any ($ f) [isNot, isSquare, isDiamond]

isBinary :: Formula a -> Bool
isBinary f = any ($ f) [isAnd, isOr, isImply, isIff]

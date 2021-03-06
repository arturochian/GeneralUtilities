modify <- function(x,
                   operations =
                       c('shift(lag = -1)',
                         '(function(a,b) a^{1/b})(2)',
                         '+1')){
    if (!is.vector(x)) stop('`x` must be a vector!')
    
    q <- parse(text = paste(c(substitute(x),operations), collapse = "%>>%"))
    return(as.numeric(eval(q, envir = parent.frame())))
}


## x <- c(1,2,3,1,2,3)
## modify(x,c('(function(x,y) x^y)(2)'))
## modify(x,
##        operations =
##        c('`+`(1)',
##          '`+`(2)',
##          '`*`(2)'))

## require(pipeR)
## iris %>>% data.table %>>% (~ iris)
## iris[, modify(Petal.Width,
##               operations =
##               c('shift(lag = -2,dif = TRUE,relative = TRUE)'))
##      , by = Species] %>>% data.frame


##' .. content for \description{} (no empty lines) ..
##'
##' .. content for \details{} ..
##' @title 
##' @param data 
##' @param by 
##' @param keepvars 
##' @param dropvars 
##' @param convert specification of commands to be applied to predefined sets of
##' variables. The syntax is as follows
##' list('`var1,var2,var3,...`~`command1`;`command2`,...',...)
##' 
##' 
##'
##' @return 
##' @author Janko Cizel
procExpand <- function(
    data = mtcars %>>% data.table,
    by = NULL,
    keepvars = NULL,
    dropvars = NULL,
    convert =
        list('~ _NUMERIC_ ~ `+`(1);`-`(2)',
             '~ _CHAR_ ~ nchar')
){
    if (!inherits(data,'data.table'))
        stop('`data` must be a data.table!')
    if (!is.null(keepvars) && !is.null(dropvars))
        stop('`keepvars` and `dropvars` cannot both be specified simultaneously!')

    ## .convert <- .parseConvert(convert)
    .convert <- .parseConvert2(convert)

    if (is.null(by)){
        .convert %>>%
        list.update(vars = .varList(data,vars,drop = dropvars)) %>>%
        list.update(vars,labs = trim(stringr::str_split(labs,",")[[1]]) %>>% .parseLabels) %>>% 
        list.update(vars,vars = trim(stringr::str_split(vars,",")[[1]])) %>>%
        list.update(oper,oper = trim(stringr::str_split(oper,";")[[1]])) %>>%        
        (~ .c)
    } else {
        .convert %>>%
        list.update(vars = .varList(data,vars,drop = if (is.null(dropvars)) by else c(dropvars,by))) %>>%
        list.update(vars = .varList(data,vars,drop = dropvars)) %>>%
        list.update(vars,labs = trim(stringr::str_split(labs,",")[[1]]) %>>% .parseLabels) %>>%      
        list.update(vars,vars = stringr::str_split(vars,",")[[1]]) %>>%
        list.update(oper,oper = trim(stringr::str_split(oper,";")[[1]])) %>>%                
        (~ .c)
    }

    out <- 
        foreach(l = 1:length(.c)) %do% {
            .l <- .c[[l]]

            if (.l$vars == "")
                return(NULL)
            
            if (is.null(by)){
                keep <-  unique(.l$vars)
                
                dt <- copy(data[,.SD,.SDcols = c(keep)])
                for (x in .l$vars){
                    dt[,paste0(x) :=
                           modify(x = as.numeric(get(x)),
                                  operations = .l$oper) %>>% as.numeric]
                    setnames(dt,
                             x,
                             paste0(.l$labs$prefix,
                                    x,
                                    .l$labs$suffix))                    
                }
                return(dt)
                
            } else {
                keep <- unique(c(.l$vars,by))
                dt <- copy(data[,.SD,.SDcols = c(keep)])
                for (x in .l$vars){
                    dt[,paste0(x) :=
                           modify(x = as.numeric(get(x)),
                                  operations = .l$oper) %>>% as.numeric,
                       by = by]
                    
                    setnames(dt,
                             x,
                             paste0(.l$labs$prefix,
                                    x,
                                    .l$labs$suffix))
                }

                dt[,paste0(by) := NULL]

                return(dt)
            }        
        }
 
    out2 <- Filter(function(x) !is.null(x), out)

    names(out2) <- NULL
    result <- do.call('cbind', out2)

    if (!is.null(by))
        result <-
            cbind(
                copy(data[,.SD,.SDcols = c(by)]),
                result
            )
    
    if (!is.null(keepvars))
        result <-
            cbind(
                copy(data[,.SD,.SDcols = c(keepvars)]),
                result
            )
   
    return(result)
}

## mtcars %>>% data.table %>>% (~ dt)
## by = 'gear'

## keepvars = c('hp','vs')
## convert <-
##     list('pre:dif.~ drat,wt ~ shift(lag=-1,dif = TRUE,relative = FALSE)',
##          'pre:dif.,suf:.rel ~ drat,wt ~ shift(lag=-1,dif = TRUE,relative = TRUE);`*`(100)')

## procExpand(
##     data = dt,
##     by = 'gear',
##     keepvars = c('mpg','drat','wt'),
##     convert = convert    
## )

.parseLabels <- function(labs = c("pre:test", "suf:test2")){
   .p <- grep("pre:",labs,value = TRUE)
   if (length(.p) == 1){
       prefix = gsub("(pre:)(.+)",
           "\\2",
           .p)
   } else prefix = ""

   .s <- grep("suf:",labs,value = TRUE)
   if (length(.p) == 1){
       suffix = gsub("(suf:)(.+)",
           "\\2",
           .s)
   } else suffix = ""

   return(list(prefix = prefix,
               suffix = suffix))
}

## by = 'gear'
## keepvars = 'cyl'
## convert =
##     list('_NUMERIC_ ~ shift(lag = -1, dif = TRUE)',
##          '_CHAR_ ~ nchar')
## convert =
##     list('__rat ~ `/`(cyl)',
##          '_CHAR_ ~ nchar')
## ## undebug(procExpand)
## ## undebug(modify)
## procExpand(
##     data = dt,
##     by = by,
##     keepvars = keepvars,
##     dropvars = NULL,
##     convert = convert,
##     prefix = '',
##     suffix = '_mod'
## )

.parseConvert <- function(convert =
                              list('var1,var2 ~ `+`1',
                                   'var3,var4 ~ `-`1')){
    p <- lapply(convert,function(x){trim(stringr::str_split(x,'~')[[1]])})

    convert %>>%
    list.map(. ~ trim(stringr::str_split(.,'~')[[1]])) %>>%
    (~ convert)
    
    o <- 
        foreach (x = 1:length(convert)) %do% {
            ## vars = stringr::str_split(string = p[[x]][[1]],',')[[1]]
            vars = p[[x]][[1]]            
            oper = p[[x]][[2]]
            list(vars = vars,
                 oper = oper)
        }
    return(o)
}


.parseConvert2 <- function(convert =
                               list('pre:, suf:~ var1,var2 ~ `+`1',
                                    'pre:, suf:~ var3,var4 ~ `-`1')){
    p <- lapply(convert,function(x){trim(stringr::str_split(x,'~')[[1]])})

    convert %>>%
    list.map(. ~ trim(stringr::str_split(.,'~')[[1]])) %>>%
    (~ p)
    
    o <- 
        foreach (x = 1:length(convert)) %do% {
            ## vars = stringr::str_split(string = p[[x]][[1]],',')[[1]]
            labs = p[[x]][[1]]            
            vars = p[[x]][[2]]            
            oper = p[[x]][[3]]
            list(labs = labs,
                 vars = vars,
                 oper = oper)
        }
    
    return(o)
}

## .parseConvert(convert)


.varList <- function(
    data,
    varsel = "_NUMERIC_",
    drop = NULL
)
{
    .specials <- function(data = data,
                          varsel = varsel,
                          drop = drop){
        o <- {
            if (varsel == '_NUMERIC_')
                names(Filter(is.numeric, data))
            else if (varsel == '_CHAR_')
                names(Filter(is.character, data))
            else if (varsel %like% "^__"){
                pattern = gsub("(__)(.+)","\\2",varsel)
                o <- names(data)[names(data) %like% pattern]
                o
            } else {
                varsel
            }
        }

        if (!is.null(drop)) o <- setdiff(o,drop)

        out <- paste0(o, collapse = ',')
        return(out)
    }

    .fun <- Vectorize(.specials,vectorize.args = 'varsel')
    
    return(.fun(data = data,
                varsel = varsel,
                drop = drop) )
}

## mtcars %>>%
## (? dt ~ .varList(dt, varsel = '_NUMERIC_')) %>>%
## (? dt ~ .varList(dt, varsel = '_CHAR_')) %>>%
## (? dt ~ .varList(dt, varsel = '__rat')) %>>%
## (? dt ~ .varList(dt, varsel = c('x,y', '_NUMERIC_')))
